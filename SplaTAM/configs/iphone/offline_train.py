# Config for offline training using data captured from the iOS app

config = {
    "workdir": "./work/offline_iphone",
    "run_name": "splatam_iphone_offline",
    "seed": 0,
    "primary_device": "cuda:0",
    "map_every": 1,
    "keyframe_every": 1,
    "mapping_window_size": 24,
    "report_global_progress_every": 50,
    "eval_every": 5,
    "scene_radius_depth_ratio": 3,
    "mean_sq_dist_method": "projective",
    "gaussian_distribution": "anisotropic",
    "load_checkpoint": False,
    "checkpoint_time_idx": 500,
    "save_checkpoints": True,
    "checkpoint_interval": 100,
    "data": {
        # IMPORTANT: Change this path to the parent directory of your captured sessions.
        # For example: "/path/to/your/captures"
        "basedir": "path/to/your/captures/parent/directory",
        # IMPORTANT: Change this to the name of the specific session folder you want to train on.
        # For example: "240711133000"
        "sequence": "your_session_folder_name",
        "dataset_name": "nerfcapture",
        "desired_image_height": 192,
        "desired_image_width": 256,
        "densification_image_height": 768,
        "densification_image_width": 1024,
        "start": 0,
        "end": -1,
        "stride": 1,
        "num_frames": -1,
    },
    "tracking": {
        "use_gt_poses": True,  # Use the poses from the capture app
        "num_iters": 10, # Less iters since we are using GT poses
        "lrs": {
            'cam_unnorm_rots': 0.0, # No need to optimize camera poses if using GT
            'cam_trans': 0.0,
        },
        "loss_weights": {
            'im': 0.0, # No need for loss if not optimizing
            'depth': 0.0,
        },
        "use_sil_for_loss": False,
        "sil_thres": 0.99,
        "use_l1": True,
        "ignore_outlier_depth_loss": False,
        "forward_prop": True,
    },
    "mapping": {
        "num_iters": 120,
        "add_new_gaussians": True,
        "sil_thres": 0.5,
        "use_l1": True,
        "use_gaussian_splatting_densification": True,
        "prune_gaussians": True,
        "loss_weights": {
            'im': 0.5,
            'depth': 1.0,
        },
        "lrs": {
            'means3D': 0.0001,
            'rgb_colors': 0.0025,
            'unnorm_rotations': 0.001,
            'logit_opacities': 0.05,
            'log_scales': 0.001,
            'cam_unnorm_rots': 0.0000,
            'cam_trans': 0.0000,
        },
        "pruning_dict": {
            'start_after': 0,
            'remove_big_after': 0,
            'stop_pruning_after': 20,
            'prune_every': 20,
            'removal_opacity_threshold': 0.4,
            'final_removal_opacity_threshold': 0.6,
            'reset_opacities': True,
            'reset_opacities_every': 500,
        },
        "densify_dict": {
            'start_after': 100,
            'remove_big_after': 3000,
            'stop_densifying_after': 5000,
            'densify_every': 100,
            'grad_thresh': 0.0002,
            'num_to_split_into': 2,
            'removal_opacity_threshold': 0.4,
            'final_removal_opacity_threshold': 0.7,
            'reset_opacities': True,
            'reset_opacities_every': 3000,
        },
    },
    "use_wandb": False,
}
