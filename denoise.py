import os
import pydicom
import shutil
from scipy import ndimage
import skimage.exposure
import numpy as np

def denoise_salt_and_pepper(image, size):
    # Perform salt and pepper denoising
    denoised_image = ndimage.median_filter(image, size)
    return denoised_image

# Path to the input directory containing DICOM files
input_directory = "images"

# Path to the output directory where denoised DICOM files will be saved
output_directory = "denoised"

for file_name in os.listdir(input_directory):
    file_path = os.path.join(input_directory, file_name)

    if file_name.upper() == "DICOMDIR":
        shutil.copy(file_path, output_directory)
        continue

    try:
        # Read DICOM file
        original_dicom = pydicom.dcmread(file_path)
        
        # Convert pixel data to float
        image = original_dicom.pixel_array.astype(float)

        # Apply gamma correction (increases the brightness of the image)
        corrected_image = skimage.exposure.adjust_gamma(image, gamma=0.5)

        denoised_image = denoise_salt_and_pepper(corrected_image, 3)

        # Replace pixel data with denoised image and adjust datatype
        new_dicom = pydicom.dcmread(file_path)  # Read the file again to keep metadata intact
        new_dicom.PixelData = denoised_image.astype(original_dicom.pixel_array.dtype).tobytes()
        new_dicom.Rows, new_dicom.Columns = denoised_image.shape

        # Additional metadata fields to aid viewers
        # Fine-tune these values based on the specific images you are working with
        new_dicom.WindowCenter = np.percentile(denoised_image, 95).astype('int16')  # Closer to max intensity
        new_dicom.WindowWidth = (np.percentile(denoised_image, 95) - np.percentile(denoised_image, 5)).astype('int16')  # Reduced range

        # Save the new DICOM file in the output directory with the same name
        output_file_path = os.path.join(output_directory, file_name)
        new_dicom.save_as(output_file_path)

    except Exception as e:
        print(f"Could not process file {file_name}: {str(e)}")

