"""
Script to run SplaTAM offline on a dataset captured with NeRFCapture or LiDAR-Depth-Map-Capture-for-iOS.
"""
#!/usr/bin/env python3

import argparse
import os
import shutil
import sys
import time
from pathlib import Path
import json
from importlib.machinery import SourceFileLoader

_BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

sys.path.insert(0, _BASE_DIR)

import cv2
import numpy as np
import torch
import torch.nn.functional as F
from tqdm import tqdm

from datasets.gradslam_datasets.geometryutils import relative_transformation
from utils.common_utils import seed_everything, save_params_ckpt, save_params
from utils.eval_helpers import report_progress
from utils.keyframe_selection import keyframe_selection_overlap
from utils.recon_helpers import setup_camera
from utils.slam_external import build_rotation, prune_gaussians, densify
from utils.slam_helpers import matrix_to_quaternion
from scripts.splatam import get_loss, initialize_optimizer, initialize_params, initialize_camera_pose, get_pointcloud, add_new_gaussians

from diff_gaussian_rasterization import GaussianRasterizer as Renderer

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="./configs/iphone/offline_train.py", type=str, help="Path to config file.")
    return parser.parse_args()

def offline_training_loop(config: dict):
    # Load the dataset
    data_dir = Path(config['data']['basedir']).resolve()
    if not data_dir.exists():
        print(f"Data directory {data_dir} not found.")
        sys.exit(1)

    # Load transforms.json
    transforms_file = data_dir / "transforms.json"
    if not transforms_file.exists():
        print(f"transforms.json not found in {data_dir}")
        sys.exit(1)

    with open(transforms_file, 'r') as f:
        manifest = json.load(f)

    frames_data = manifest['frames']
    num_frames = len(frames_data)
    if 'num_frames' in config:
        num_frames = min(num_frames, config['num_frames'])
        frames_data = frames_data[:num_frames]
    else:
        config['num_frames'] = num_frames

    print(f"Processing {num_frames} frames from the dataset.")

    # Initialize list to keep track of Keyframes
    keyframe_list = []
    keyframe_time_indices = []

    # Init Variables to keep track of ARkit poses and runtimes
    gt_w2c_all_frames = []
    tracking_iter_time_sum = 0
    tracking_iter_time_count = 0
    mapping_iter_time_sum = 0
    mapping_iter_time_count = 0
    tracking_frame_time_sum = 0
    tracking_frame_time_count = 0
    mapping_frame_time_sum = 0
    mapping_frame_time_count = 0
    P = torch.tensor(
        [
            [1, 0, 0, 0],
            [0, -1, 0, 0],
            [0, 0, -1, 0],
            [0, 0, 0, 1]
        ]
    ).float()

    # Start Offline Training Loop
    for time_idx, frame_data in enumerate(tqdm(frames_data, desc="Processing Frames")):
        # Load RGB
        rgb_path = data_dir / frame_data['file_path']
        image = cv2.imread(str(rgb_path))
        if image is None:
            print(f"Could not read image {rgb_path}")
            continue
        image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

        # Load Depth
        depth_path = data_dir / frame_data['depth_path']
        if not depth_path.exists():
            print(f"No Depth Image found at {depth_path}. Skipping Frame...")
            continue
        
        if str(depth_path).endswith('.tiff'):
            curr_depth = cv2.imread(str(depth_path), -1)
            if curr_depth is not None:
                curr_depth = curr_depth.astype(np.float32) * manifest.get('integer_depth_scale', 1.0)
        else:
             curr_depth = np.asarray(cv2.imread(str(depth_path), cv2.IMREAD_UNCHANGED), dtype=np.uint8).view(
                    dtype=np.float32).reshape((manifest['h'], manifest['w']))

        if curr_depth is None:
            print(f"Could not read depth image {depth_path}")
            continue

        # ARKit Poses
        X_WV = np.asarray(frame_data['transform_matrix'], dtype=np.float32)
        
        # Convert ARKit Pose to GradSLAM format
        gt_pose = torch.from_numpy(X_WV).float()
        gt_pose = P @ gt_pose @ P.T
        if time_idx == 0:
            first_abs_gt_pose = gt_pose
        gt_pose = relative_transformation(first_abs_gt_pose.unsqueeze(0), gt_pose.unsqueeze(0), orthogonal_rotations=False)
        gt_w2c = torch.linalg.inv(gt_pose[0])
        gt_w2c_all_frames.append(gt_w2c)
        
        # Initialize Tracking & Mapping Resolution Data
        color = cv2.resize(image, dsize=(
            config['data']['desired_image_width'], config['data']['desired_image_height']), interpolation=cv2.INTER_LINEAR)
        depth = cv2.resize(curr_depth, dsize=(
                config['data']['desired_image_width'], config['data']['desired_image_height']), interpolation=cv2.INTER_NEAREST)
        depth = np.expand_dims(depth, -1)
        color = torch.from_numpy(color).cuda().float()
        color = color.permute(2, 0, 1) / 255
        depth = torch.from_numpy(depth).cuda().float()
        depth = depth.permute(2, 0, 1)
        if time_idx == 0:
            intrinsics = torch.tensor([[manifest['fl_x'], 0, manifest['cx']], [0, manifest['fl_y'], manifest['cy']], [0, 0, 1]]).cuda().float()
            intrinsics = intrinsics / config['data']['downscale_factor']
            intrinsics[2, 2] = 1.0
            first_frame_w2c = torch.eye(4).cuda().float()
            cam = setup_camera(color.shape[2], color.shape[1], intrinsics.cpu().numpy(), first_frame_w2c.cpu().numpy())
        
        # Initialize Densification Resolution Data
        densify_color = cv2.resize(image, dsize=(
            config['data']['densification_image_width'], config['data']['densification_image_height']), interpolation=cv2.INTER_LINEAR)
        densify_depth = cv2.resize(curr_depth, dsize=(
            config['data']['densification_image_width'], config['data']['densification_image_height']), interpolation=cv2.INTER_NEAREST)
        densify_depth = np.expand_dims(densify_depth, -1)
        densify_color = torch.from_numpy(densify_color).cuda().float()
        densify_color = densify_color.permute(2, 0, 1) / 255
        densify_depth = torch.from_numpy(densify_depth).cuda().float()
        densify_depth = densify_depth.permute(2, 0, 1)
        if time_idx == 0:
            densify_intrinsics = torch.tensor([[manifest['fl_x'], 0, manifest['cx']], [0, manifest['fl_y'], manifest['cy']], [0, 0, 1]]).cuda().float()
            densify_intrinsics = densify_intrinsics / config['data']['densify_downscale_factor']
            densify_intrinsics[2, 2] = 1.0
            densify_cam = setup_camera(densify_color.shape[2], densify_color.shape[1], densify_intrinsics.cpu().numpy(), first_frame_w2c.cpu().numpy())
        
        # Initialize Params for first time step
        if time_idx == 0:
            # Get Initial Point Cloud
            mask = (densify_depth > 0) # Mask out invalid depth values
            mask = mask.reshape(-1)
            init_pt_cld, mean3_sq_dist = get_pointcloud(densify_color, densify_depth, densify_intrinsics, first_frame_w2c, 
                                                        mask=mask, compute_mean_sq_dist=True, 
                                                        mean_sq_dist_method=config['mean_sq_dist_method'])
            params, variables = initialize_params(init_pt_cld, num_frames, mean3_sq_dist, config['gaussian_distribution'])
            variables['scene_radius'] = torch.max(densify_depth)/config['scene_radius_depth_ratio']
        
        # Initialize Mapping & Tracking for current frame
        iter_time_idx = time_idx
        curr_gt_w2c = gt_w2c_all_frames
        curr_data = {'cam': cam, 'im': color, 'depth':depth, 'id': iter_time_idx, 
                     'intrinsics': intrinsics, 'w2c': first_frame_w2c, 'iter_gt_w2c_list': curr_gt_w2c}
        tracking_curr_data = curr_data
        
        # Optimization Iterations
        num_iters_mapping = config['mapping']['num_iters']
        
        # Initialize the camera pose for the current frame
        if time_idx > 0:
            params = initialize_camera_pose(params, time_idx, forward_prop=config['tracking']['forward_prop'])

        # Tracking
        tracking_start_time = time.time()
        if time_idx > 0 and not config['tracking']['use_gt_poses']:
            optimizer = initialize_optimizer(params, config['tracking']['lrs'], tracking=True)
            candidate_cam_unnorm_rot = params['cam_unnorm_rots'][..., time_idx].detach().clone()
            candidate_cam_tran = params['cam_trans'][..., time_idx].detach().clone()
            current_min_loss = float(1e20)
            iter = 0
            do_continue_slam = False
            num_iters_tracking = config['tracking']['num_iters']
            progress_bar_tracking = tqdm(range(num_iters_tracking), desc=f"Tracking Time Step: {time_idx}")
            while True:
                iter_start_time = time.time()
                loss, variables, losses = get_loss(params, tracking_curr_data, variables, iter_time_idx, config['tracking']['loss_weights'],
                                                config['tracking']['use_sil_for_loss'], config['tracking']['sil_thres'],
                                                config['tracking']['use_l1'], config['tracking']['ignore_outlier_depth_loss'], tracking=True, 
                                                visualize_tracking_loss=config['tracking']['visualize_tracking_loss'],
                                                tracking_iteration=iter)
                loss.backward()
                optimizer.step()
                optimizer.zero_grad(set_to_none=True)
                with torch.no_grad():
                    if loss < current_min_loss:
                        current_min_loss = loss
                        candidate_cam_unnorm_rot = params['cam_unnorm_rots'][..., time_idx].detach().clone()
                        candidate_cam_tran = params['cam_trans'][..., time_idx].detach().clone()
                    if config['report_iter_progress']:
                        report_progress(params, tracking_curr_data, iter+1, progress_bar_tracking, iter_time_idx, sil_thres=config['tracking']['sil_thres'], tracking=True)
                    else:
                        progress_bar_tracking.update(1)
                iter_end_time = time.time()
                tracking_iter_time_sum += iter_end_time - iter_start_time
                tracking_iter_time_count += 1
                iter += 1
                if iter == num_iters_tracking:
                    if losses['depth'] < config['tracking']['depth_loss_thres'] and config['tracking']['use_depth_loss_thres']:
                        break
                    elif config['tracking']['use_depth_loss_thres'] and not do_continue_slam:
                        do_continue_slam = True
                        progress_bar_tracking = tqdm(range(num_iters_tracking), desc=f"Tracking Time Step: {time_idx}")
                        num_iters_tracking = 2*num_iters_tracking
                    else:
                        break
            progress_bar_tracking.close()
            with torch.no_grad():
                params['cam_unnorm_rots'][..., time_idx] = candidate_cam_unnorm_rot
                params['cam_trans'][..., time_idx] = candidate_cam_tran
        elif time_idx > 0 and config['tracking']['use_gt_poses']:
            with torch.no_grad():
                rel_w2c = curr_gt_w2c[-1]
                rel_w2c_rot = rel_w2c[:3, :3].unsqueeze(0).detach()
                rel_w2c_rot_quat = matrix_to_quaternion(rel_w2c_rot)
                rel_w2c_tran = rel_w2c[:3, 3].detach()
                params['cam_unnorm_rots'][..., time_idx] = rel_w2c_rot_quat
                params['cam_trans'][..., time_idx] = rel_w2c_tran
        tracking_end_time = time.time()
        tracking_frame_time_sum += tracking_end_time - tracking_start_time
        tracking_frame_time_count += 1

        if time_idx == 0 or (time_idx+1) % config['report_global_progress_every'] == 0:
            try:
                progress_bar_eval = tqdm(range(1), desc=f"Tracking Result Time Step: {time_idx}")
                with torch.no_grad():
                    report_progress(params, tracking_curr_data, 1, progress_bar_eval, iter_time_idx, sil_thres=config['tracking']['sil_thres'], tracking=True)
                progress_bar_eval.close()
            except:
                ckpt_output_dir = Path(config["workdir"]) / "checkpoints"
                os.makedirs(ckpt_output_dir, exist_ok=True)
                save_params_ckpt(params, ckpt_output_dir, time_idx)
                print('Failed to evaluate trajectory.')
        
        if time_idx == 0 or (time_idx+1) % config['map_every'] == 0:
            if config['mapping']['add_new_gaussians'] and time_idx > 0:
                densify_curr_data = {'cam': densify_cam, 'im': densify_color, 'depth': densify_depth, 'id': time_idx, 
                            'intrinsics': densify_intrinsics, 'w2c': first_frame_w2c, 'iter_gt_w2c_list': curr_gt_w2c}
                params, variables = add_new_gaussians(params, variables, densify_curr_data, 
                                                    config['mapping']['sil_thres'], time_idx,
                                                    config['mean_sq_dist_method'], config['gaussian_distribution'])
            
            with torch.no_grad():
                curr_cam_rot = F.normalize(params['cam_unnorm_rots'][..., time_idx].detach())
                curr_cam_tran = params['cam_trans'][..., time_idx].detach()
                curr_w2c = torch.eye(4).cuda().float()
                curr_w2c[:3, :3] = build_rotation(curr_cam_rot)
                curr_w2c[:3, 3] = curr_cam_tran
                num_keyframes = config['mapping_window_size']-2
                selected_keyframes = keyframe_selection_overlap(depth, curr_w2c, intrinsics, keyframe_list[:-1], num_keyframes)
                selected_time_idx = [keyframe_list[frame_idx]['id'] for frame_idx in selected_keyframes]
                if len(keyframe_list) > 0:
                    selected_time_idx.append(keyframe_list[-1]['id'])
                    selected_keyframes.append(len(keyframe_list)-1)
                selected_time_idx.append(time_idx)
                selected_keyframes.append(-1)
                # print(f"\nSelected Keyframes at Frame {time_idx}: {selected_time_idx}")

            optimizer = initialize_optimizer(params, config['mapping']['lrs'], tracking=False) 

            mapping_start_time = time.time()
            if num_iters_mapping > 0:
                progress_bar_mapping = tqdm(range(num_iters_mapping), desc=f"Mapping Time Step: {time_idx}")
            for iter in range(num_iters_mapping):
                iter_start_time = time.time()
                rand_idx = np.random.randint(0, len(selected_keyframes))
                selected_rand_keyframe_idx = selected_keyframes[rand_idx]
                if selected_rand_keyframe_idx == -1:
                    iter_time_idx = time_idx
                    iter_color = color
                    iter_depth = depth
                else:
                    iter_time_idx = keyframe_list[selected_rand_keyframe_idx]['id']
                    iter_color = keyframe_list[selected_rand_keyframe_idx]['color']
                    iter_depth = keyframe_list[selected_rand_keyframe_idx]['depth']
                iter_gt_w2c = gt_w2c_all_frames[:iter_time_idx+1]
                iter_data = {'cam': cam, 'im': iter_color, 'depth': iter_depth, 'id': iter_time_idx, 
                            'intrinsics': intrinsics, 'w2c': first_frame_w2c, 'iter_gt_w2c_list': iter_gt_w2c}
                loss, variables, losses = get_loss(params, iter_data, variables, iter_time_idx, config['mapping']['loss_weights'],
                                                config['mapping']['use_sil_for_loss'], config['mapping']['sil_thres'],
                                                config['mapping']['use_l1'], config['mapping']['ignore_outlier_depth_loss'], mapping=True)
                loss.backward()
                with torch.no_grad():
                    if config['mapping']['prune_gaussians']:
                        params, variables = prune_gaussians(params, variables, optimizer, iter, config['mapping']['pruning_dict'])
                    if config['mapping']['use_gaussian_splatting_densification']:
                        params, variables = densify(params, variables, optimizer, iter, config['mapping']['densify_dict'])
                    optimizer.step()
                    optimizer.zero_grad(set_to_none=True)
                    if config['report_iter_progress']:
                        report_progress(params, iter_data, iter+1, progress_bar_mapping, iter_time_idx, sil_thres=config['mapping']['sil_thres'], 
                                        mapping=True, online_time_idx=time_idx)
                    else:
                        progress_bar_mapping.update(1)
                iter_end_time = time.time()
                mapping_iter_time_sum += iter_end_time - iter_start_time
                mapping_iter_time_count += 1
            if num_iters_mapping > 0:
                progress_bar_mapping.close()
            mapping_end_time = time.time()
            mapping_frame_time_sum += mapping_end_time - mapping_start_time
            mapping_frame_time_count += 1

            if time_idx == 0 or (time_idx+1) % config['report_global_progress_every'] == 0:
                try:
                    progress_bar_eval_map = tqdm(range(1), desc=f"Mapping Result Time Step: {time_idx}")
                    with torch.no_grad():
                        report_progress(params, curr_data, 1, progress_bar_eval_map, time_idx, sil_thres=config['mapping']['sil_thres'], 
                                        mapping=True, online_time_idx=time_idx)
                    progress_bar_eval_map.close()
                except:
                    ckpt_output_dir = Path(config["workdir"]) / "checkpoints"
                    os.makedirs(ckpt_output_dir, exist_ok=True)
                    save_params_ckpt(params, ckpt_output_dir, time_idx)
                    print('Failed to evaluate trajectory.')

        if ((time_idx == 0) or ((time_idx+1) % config['keyframe_every'] == 0) or \
                    (time_idx == num_frames-1)) and (not torch.isinf(curr_gt_w2c[-1]).any()) and (not torch.isnan(curr_gt_w2c[-1]).any()):
            with torch.no_grad():
                curr_cam_rot = F.normalize(params['cam_unnorm_rots'][..., time_idx].detach())
                curr_cam_tran = params['cam_trans'][..., time_idx].detach()
                curr_w2c = torch.eye(4).cuda().float()
                curr_w2c[:3, :3] = build_rotation(curr_cam_rot)
                curr_w2c[:3, 3] = curr_cam_tran
                curr_keyframe = {'id': time_idx, 'est_w2c': curr_w2c, 'color': color, 'depth': depth}
                keyframe_list.append(curr_keyframe)
                keyframe_time_indices.append(time_idx)
        
        if time_idx % config["checkpoint_interval"] == 0 and config['save_checkpoints']:
            ckpt_output_dir = Path(config["workdir"]) / "checkpoints"
            save_params_ckpt(params, ckpt_output_dir, time_idx)
            np.save(os.path.join(ckpt_output_dir, f"keyframe_time_indices{time_idx}.npy"), np.array(keyframe_time_indices))

        torch.cuda.empty_cache()

    # Compute Average Runtimes
    if tracking_iter_time_count == 0: tracking_iter_time_count = 1
    if tracking_frame_time_count == 0: tracking_frame_time_count = 1
    if mapping_iter_time_count == 0: mapping_iter_time_count = 1
    if mapping_frame_time_count == 0: mapping_frame_time_count = 1
    tracking_iter_time_avg = tracking_iter_time_sum / tracking_iter_time_count
    tracking_frame_time_avg = tracking_frame_time_sum / tracking_frame_time_count
    mapping_iter_time_avg = mapping_iter_time_sum / mapping_iter_time_count
    mapping_frame_time_avg = mapping_frame_time_sum / mapping_frame_time_count
    print(f"\nAverage Tracking/Iteration Time: {tracking_iter_time_avg*1000} ms")
    print(f"Average Tracking/Frame Time: {tracking_frame_time_avg} s")
    print(f"Average Mapping/Iteration Time: {mapping_iter_time_avg*1000} ms")
    print(f"Average Mapping/Frame Time: {mapping_frame_time_avg} s")

    # Add Camera Parameters to Save them
    params['timestep'] = variables['timestep']
    params['intrinsics'] = intrinsics.detach().cpu().numpy()
    params['w2c'] = first_frame_w2c.detach().cpu().numpy()
    params['org_width'] = config['data']["desired_image_width"]
    params['org_height'] = config['data']["desired_image_height"]
    params['gt_w2c_all_frames'] = []
    for gt_w2c_tensor in gt_w2c_all_frames:
        params['gt_w2c_all_frames'].append(gt_w2c_tensor.detach().cpu().numpy())
    params['gt_w2c_all_frames'] = np.stack(params['gt_w2c_all_frames'], axis=0)
    params['keyframe_time_indices'] = np.array(keyframe_time_indices)
    
    # Save Parameters
    output_dir = (Path(config["workdir"]) / config["run_name"]).resolve()
    save_params(params, str(output_dir))
    print("Saved SplaTAM Splat to: ", str(output_dir))


if __name__ == "__main__":
    args = parse_args()

    # Load SplaTAM config
    experiment = SourceFileLoader(
        os.path.basename(args.config), args.config
    ).load_module()

    # Set Seed
    seed_everything(seed=experiment.config['seed'])

    # Create Results Directory and Copy Config
    results_dir = (Path(experiment.config["workdir"]) / experiment.config["run_name"]).resolve()
    if not experiment.config['load_checkpoint']:
        results_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy(args.config, results_dir / "config.py")

    config = experiment.config
    if "gaussian_distribution" not in config:
        config['gaussian_distribution'] = "isotropic"
    
    offline_training_loop(config)
