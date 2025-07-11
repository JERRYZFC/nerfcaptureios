import glob
import json
import os
from pathlib import Path
from typing import Dict, List, Optional, Union

import numpy as np
import torch
from natsort import natsorted

from .basedataset import GradSLAMDataset


def create_filepath_index_mapping(frames):
    return {frame["file_path"]: index for index, frame in enumerate(frames)}


class NeRFCaptureDataset(GradSLAMDataset):
    def __init__(
        self,
        basedir,
        sequence,
        stride: Optional[int] = None,
        start: Optional[int] = 0,
        end: Optional[int] = -1,
        desired_height: Optional[int] = 1440,
        desired_width: Optional[int] = 1920,
        load_embeddings: Optional[bool] = False,
        embedding_dir: Optional[str] = "embeddings",
        embedding_dim: Optional[int] = 512,
        **kwargs,
    ):
        self.input_folder = os.path.join(basedir, sequence)
        config_dict = {}
        config_dict["dataset_name"] = "nerfcapture"
        self.pose_path = None
        
        # Load NeRFStudio format camera & poses data
        self.cams_metadata = self.load_cams_metadata()
        self.frames_metadata = self.cams_metadata["frames"]
        self.filepath_index_mapping = create_filepath_index_mapping(self.frames_metadata)

        # Load RGB & Depth filepaths
        self.image_names = natsorted(os.listdir(f"{self.input_folder}/rgb"))
        self.image_names = [f'rgb/{image_name}' for image_name in self.image_names]

        # Init Intrinsics
        config_dict["camera_params"] = {}
        config_dict["camera_params"]["png_depth_scale"] = 1.0 # Depth is in meters
        config_dict["camera_params"]["image_height"] = self.cams_metadata["h"]
        config_dict["camera_params"]["image_width"] = self.cams_metadata["w"]
        config_dict["camera_params"]["fx"] = self.cams_metadata["fl_x"]
        config_dict["camera_params"]["fy"] = self.cams_metadata["fl_y"]
        config_dict["camera_params"]["cx"] = self.cams_metadata["cx"]
        config_dict["camera_params"]["cy"] = self.cams_metadata["cy"]

        super().__init__(
            config_dict,
            stride=stride,
            start=start,
            end=end,
            desired_height=desired_height,
            desired_width=desired_width,
            load_embeddings=load_embeddings,
            embedding_dir=embedding_dir,
            embedding_dim=embedding_dim,
            **kwargs,
        ) 

    def load_cams_metadata(self):
        cams_metadata_path = f"{self.input_folder}/transforms.json"
        cams_metadata = json.load(open(cams_metadata_path, "r"))
        return cams_metadata
    
    def get_filepaths(self):
        base_path = f"{self.input_folder}"
        color_paths = []
        depth_paths = []
        self.tmp_poses = []
        P = torch.tensor(
            [
                [1, 0, 0, 0],
                [0, -1, 0, 0],
                [0, 0, -1, 0],
                [0, 0, 0, 1]
            ]
        ).float()
        for image_name in self.image_names:
            # Search for image name in frames_metadata
            frame_metadata = self.frames_metadata[self.filepath_index_mapping.get(image_name)]
            # Get path of image and depth
            color_path = f"{base_path}/{image_name}"
            # Correctly form the depth path by replacing the folder and the extension
            depth_filename = os.path.splitext(os.path.basename(image_name))[0] + ".tiff"
            depth_path = os.path.join(base_path, "depth", depth_filename)
            color_paths.append(color_path)
            depth_paths.append(depth_path)
            # Get pose of image in GradSLAM format
            c2w = torch.from_numpy(np.array(frame_metadata["transform_matrix"])).float()
            _pose = P @ c2w @ P.T
            self.tmp_poses.append(_pose)
        embedding_paths = None
        if self.load_embeddings:
            embedding_paths = natsorted(glob.glob(f"{base_path}/{self.embedding_dir}/*.pt"))
        return color_paths, depth_paths, embedding_paths

    def load_poses(self):
        return self.tmp_poses

    def read_embedding_from_file(self, embedding_file_path):
        print(embedding_file_path)
        embedding = torch.load(embedding_file_path, map_location="cpu")
        return embedding.permute(0, 2, 3, 1)  # (1, H, W, embedding_dim)
