import trimesh
import numpy as np
from PIL import Image
import io

class TextureMapper:
    def __init__(self, smplx_model_path: str):
        self.smplx_model_path = smplx_model_path
        
    def map_texture_to_mesh(self, texture_image: Image.Image, output_path: str = "textured_body.glb"):
        """
        Wraps a 2D try-on image onto a 3D SMPL-X body mesh.
        
        Args:
            texture_image: The 2D VTO result image (PIL Image).
            output_path: Path to save the textured .glb file.
            
        Returns:
            Path to the saved .glb file.
        """
        # Load the base SMPL-X mesh
        mesh = trimesh.load(self.smplx_model_path, process=False)
        
        # Convert PIL image to numpy array for texture
        texture_array = np.array(texture_image)
        
        # Create a texture object
        material = trimesh.visual.texture.SimpleMaterial(image=Image.fromarray(texture_array))
        
        # Apply texture to mesh using UV coordinates
        # Note: This assumes the SMPL-X mesh has UV coordinates.
        # If not, we generate a simple spherical UV map.
        if not hasattr(mesh.visual, 'uv') or mesh.visual.uv is None:
            mesh.visual = trimesh.visual.texture.TextureVisuals(
                uv=trimesh.util.generate_spherical_uv(mesh.vertices),
                material=material
            )
        else:
            mesh.visual.material = material
            
        # Export as GLB for mobile/web viewing
        glb_data = mesh.export(file_type='glb')
        
        with open(output_path, 'wb') as f:
            f.write(glb_data)
            
        return output_path
