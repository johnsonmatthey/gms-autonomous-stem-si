# Zaeem Najeeb @ Johnson Matthey Technology Centre, University of Oxford
# Liam Spillane @ Gatan Inc.
# Date: 04/06/2025
# version:20250604, v1.0
################################################################################
print("\nPython Initialise")

import numpy as np 
from skimage import io, filters, measure
import cv2
from scipy import ndimage
from skimage.segmentation import clear_border
import matplotlib.pyplot as plt
import sys


################################################################################
#
#			USER Global Parameters
#
################################################################################
# HARD CODED Host and Port used for UNET communication if code is provided
HOST = '10.183.0.15'
PORT = 8090

# Pixel size and unit should be set automatically
HIST_BIN_WIDTH = 0.5          # Histograma bin width for PSA
USE_UNET = False              # Use unet or manual thresholding - will do manual if UNET fail connecion
SHOW_THRESH_MASK = True       # Whether to display in DM the mask determined via UNET/Thresholding
REMOVE_EDGES = True           # Remove particles touching the edge of the image
PAD_FACTOR = 0.1              # Increase bbox size by 10% if desired
MINIMUM_DIAMETER = 10         # Ignore objects in mask with diameter less than this in pixels


################################################################################
#
#			Program Global Parameters
#
################################################################################
# Paths and filenames for tags
PERSISTENT_FILEPATH_TAG = "SIMA:Filepath"        # Set by the .s script
PERSISTENT_SURVEYID_TAG = "SIMA:SurveyImageID"   # Set by the .s script
PERSISTENT_TEMPERATURE_TAG = "SIMA:Temperature"  # Set by the .s script; optional, omitted from plot if absent
PERSISTENT_SCANDIR_TAG = "SIMA:ScanOutputDir"    # Set by the .s script
PERSISTENT_SCANPREFIX_TAG = "SIMA:ScanOutputPrefix" # Set by the .s script
PERSISTENT_PSDFILENAME_TAG = "SIMA:PSDFilename"  # Set by the .s script
################################################################################

def bytescale(data, cmin=None, cmax=None, high=255, low=0):
    """
    Source:
    https://docs.scipy.org/doc/scipy-1.2.1/reference/generated/scipy.misc.bytescale.html
    """
    if data.dtype == np.uint8:
        return data

    if high < low:
        raise ValueError("`high` should be larger than `low`.")

    if cmin is None:
        cmin = data.min()
    if cmax is None:
        cmax = data.max()

    cscale = cmax - cmin
    if cscale < 0:
        raise ValueError("`cmax` should be larger than `cmin`.")
    elif cscale == 0:
        cscale = 1

    scale = float(high - low) / cscale
    bytedata = (data * 1.0 - cmin) * scale + 0.4999
    bytedata[bytedata > high] = high
    bytedata[bytedata < 0] = 0
    return np.cast[np.uint8](bytedata) + np.cast[np.uint8](low)

def remove_border_objects(mask:np.ndarray)->np.ndarray:
    """
    remove the border objects from a binary image

    Args:
        mask (np.ndarray): the mask

    Returns:
        np.ndarray: mask with border objects removed
    """
    return clear_border(mask).astype('uint8')

def gauss_(image:np.ndarray,ks:float)->np.ndarray:
    """
    substracts a gaussian background from the image using Sergio Lozano's method

    Args:
        image (np.ndarray): image array
        ks (float): kernel size 

    Returns:
        np.ndarray: filtered image
    """
    imagef = filters.gaussian(image,ks,preserve_range=True)
    return imagef

def rb_bgs(image:np.ndarray, ks:int):
    """
    subtracts a background using the top-hat method, should be 95% similar to the rolling ball method but much faster

    Args:
        image (np.ndarray): image array
        ks (int): kernel size

    Returns:
        np.ndarray: background-subtracted image
    """
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ks, ks))
    return cv2.morphologyEx(image, cv2.MORPH_TOPHAT, kernel)

def threshold_mask(image_np, remove_edges=True):
    procdata = gauss_(image_np, ks=1)
    procdata = bytescale(rb_bgs(procdata, ks=50))
    threshold   = filters.threshold_otsu(procdata)  # Calculate threshold
    mask        = procdata > threshold              # Apply threshold

    if remove_edges:
        mask = remove_border_objects(mask)          # Remove objects touching the border
    # Close gaps between nearby features
    mask = ndimage.binary_closing(mask, structure=np.ones((5,5)))
    # Remove small objects/noise
    mask = ndimage.binary_opening(mask, structure=np.ones((3,3)))
    return mask

def get_unet_mask(img_np, remove_edges=True):
    """
    Given a numpy array, send it to the server and receive the UNet mask.
    """
    try:
        raise NotImplementedError("UNET mask code is not implemented in the public ver.")

    except Exception as e:
        print(f"UNET mask generation error: {e}. Using threshold mask instead.")
        unet_mask = threshold_mask(img_np, remove_edges=remove_edges)

    return unet_mask

def serpentine_ordering(point_arr):
    """
    Reorders a 2D array of coordinates in a serpentine pattern. Assumes point_arr is of form [[x1, y1], [x2, y2], ...].
    """
    ordered_coords = []
    current_y = point_arr[0][1]  # Start with first y-coordinate
    current_row = []
    reverse = False  # Track whether to reverse the current row

    # Iterate through coordinates
    for coord in point_arr:
        x, y = coord
        
        if y != current_y:
            # When y changes, add current row (reversed if needed) and start new row
            if reverse:
                current_row.reverse()
            ordered_coords.extend(current_row)
            current_row = []
            current_y = y
            reverse = not reverse  # Toggle reverse flag for next row

        current_row.append(coord)

    # add the last row
    if reverse:
        current_row.reverse()
    ordered_coords.extend(current_row)

    return np.array(ordered_coords)

print("Python package load complete\n")

#-------------------------------------------------------------------------------------------------------

# Now determine masks and scans
globalTags = DM.GetPersistentTagGroup()
success, strVal = globalTags.GetTagAsString(PERSISTENT_FILEPATH_TAG)
if ( success ):
    working_dir = strVal.replace("\\", "/")
else:
    print( 'The persistent tag [',PERSISTENT_FILEPATH_TAG,'] was not found or not of valid type.', sep="" )

_, ID = globalTags.GetTagAsLong(PERSISTENT_SURVEYID_TAG)
has_temp, temp_C = globalTags.GetTagAsDouble(PERSISTENT_TEMPERATURE_TAG)

scandir_found, scandir_val = globalTags.GetTagAsString(PERSISTENT_SCANDIR_TAG)
if ( scandir_found ):
    SCAN_OUTPUT_DIR = scandir_val.replace("\\", "/")
else:
    print( 'The persistent tag [',PERSISTENT_SCANDIR_TAG,'] was not found or not of valid type.', sep="" )

scanprefix_found, scanprefix_val = globalTags.GetTagAsString(PERSISTENT_SCANPREFIX_TAG)
if ( scanprefix_found ):
    SCAN_OUTPUT_PREFIX = scanprefix_val
else:
    print( 'The persistent tag [',PERSISTENT_SCANPREFIX_TAG,'] was not found or not of valid type.', sep="" )

psdfilename_found, psdfilename_val = globalTags.GetTagAsString(PERSISTENT_PSDFILENAME_TAG)
if ( psdfilename_found ):
    OUTPUT_TAG_FILENAME = psdfilename_val
else:
    print( 'The persistent tag [',PERSISTENT_PSDFILENAME_TAG,'] was not found or not of valid type.', sep="" )

# print(strVal)
# print(ID)

img = DM.FindImageByID(ID) 
procdata    = bytescale(img.GetNumArray())
origin, pixel_size, pixel_unit = img.GetDimensionCalibration(0, 0)  
pixel_size = float(f"{pixel_size:.2g}") # 2 sigfigs

#Segmentation 
if USE_UNET:
    print("attempting UNET for segmentation")
    mask = get_unet_mask(procdata, remove_edges=REMOVE_EDGES)
else:
    print("Manual thresholding for segmentation")
    mask = threshold_mask(procdata, remove_edges=REMOVE_EDGES)
# mask = ndimage.binary_dilation(mask, structure=np.ones((3,3)))  # Dilate by 1 pixel to help with boundaries
mask = measure.label(mask, connectivity=2)

# Optionally, show the mask
if SHOW_THRESH_MASK:
    img = DM.CreateImage((mask>0).astype(int))
    img.ShowImage()

# Get bbox and reorder into [y1, x1, y2, x2] format (aka [top, left, bottom, right])
measurements = measure.regionprops_table(mask, properties=['bbox', 'equivalent_diameter_area'])
bboxs_array_fi = np.c_[measurements['bbox-0'],measurements['bbox-1'], measurements['bbox-2'], measurements['bbox-3']] 

print(str(len(bboxs_array_fi)) + " particles identified\n")
if len(bboxs_array_fi) == 0:
    raise ValueError("No particles found in the image.")

#Output to Taglist
tg = DM.NewTagList()
totalParticles = len(measurements['bbox-0'])
counter_found = 0
for i in range(totalParticles):
    diameter = measurements['equivalent_diameter_area'][i]
    d = int(diameter)
    if d > MINIMUM_DIAMETER:
        print("Particle " + str(i) + ": diameter = " + str(d) + "\tadding to capture list" )

        top, left, bottom, right = bboxs_array_fi[i]
        width = right - left
        height = bottom - top
        pad_x = int(width * PAD_FACTOR)
        pad_y = int(height * PAD_FACTOR)
        # Apply padding while ensuring we don't go outside image boundaries
        padded_left = max(0, left - pad_x)
        padded_top = max(0, top - pad_y)
        padded_right = min(mask.shape[1], right + pad_x)
        padded_bottom = min(mask.shape[0], bottom + pad_y)

        # Check for 2 issues in GMS - 2 conditions must be met
        # 1. The padded width and height must be >= 16
        # 2. The padded height must be even (this will become the width of the EELS scan)
        # Ensure minimum size of 16x16 - Assume that the scan size is 16x16 or larger
        # Just increase padding appropriately, where particle will always be enclosed
        padded_height = padded_bottom - padded_top
        padded_width = padded_right - padded_left
        if padded_height < 16:
            needed_increase = 16 - padded_height
            # Try to increase bottom first
            if padded_bottom + needed_increase <= mask.shape[0]:
                padded_bottom += needed_increase
            # If can't increase bottom, decrease top
            else:
                padded_top = max(0, padded_top - needed_increase)
        
        if padded_width < 16:
            needed_increase = 16 - padded_width
            # Try to increase right first
            if padded_right + needed_increase <= mask.shape[1]:
                padded_right += needed_increase
            # If can't increase right, decrease left
            else:
                padded_left = max(0, padded_left - needed_increase)

        # Ensure padded height (defined as width here) is even - AVOIDS ISSUE IN CUSTOM SCAN!
        padded_width = padded_right - padded_left #recalculate given the new values
        if padded_width % 2 != 0:
            # If we're at the bottom edge of the image, adjust top
            if padded_right >= mask.shape[1]:
                if padded_left > 0:
                    padded_left -= 1
            # Otherwise adjust bottom
            else:
                padded_right += 1

        # Store padded bbox coords for later use in scan
        tg.InsertTagAsLongRect(i, padded_top, padded_left, padded_bottom, padded_right)

        # Now define the scan pattern
        tg_scan = DM.NewTagList()

        bbox_region = mask[padded_top:padded_bottom, padded_left:padded_right]
        bbox_region_particle_coords = np.argwhere(bbox_region == i + 1).astype(int) #NOTE THIS IS NOW TRANSPOSED!!!!
        # [Y1,X1], [Y2,X2] etc
        # Must sort based on first column
        bbox_region_particle_coords = np.array(sorted(bbox_region_particle_coords, key=lambda x: (x[0], x[1])))
        
        #img = DM.CreateImage(bbox_region.astype(int))
        #img.ShowImage()
        
        bbox_coords_ordered = serpentine_ordering(bbox_region_particle_coords)
        #reverse ordering as first element added will be last element in taglist
        bbox_coords_ordered = bbox_coords_ordered[::-1] 
        for y_coord, x_coord in bbox_coords_ordered:
            # NOTE swapped as inverted axis in GMS compared to here
            #Place the data point before the 0 index. This will fill it up backwards
            tg_scan.InsertTagAsShortPoint(0, x_coord, y_coord) #Place the data point before the 0 index.
            
        #Save taglist to file
        fullpath = SCAN_OUTPUT_DIR + SCAN_OUTPUT_PREFIX + str(counter_found)
        print(fullpath)
        tg_scan.SaveToFile(fullpath)

        # if counter_found == 2: # Limit to first 3 particles
        #     break
        # np.save(fullpath, bbox_coords_ordered)

        counter_found += 1


#Save TagList to File
fullpath        = working_dir + OUTPUT_TAG_FILENAME
tg.SaveToFile(fullpath)

# Now do matplotlib plotting
if not any(arg == '-a' for arg in sys.argv):
    sys.argv.extend(['-a', ' '])        

fig1, ax1 = plt.subplots(figsize=(4, 4))
diameters = np.array(measurements['equivalent_diameter_area'])
diameters_filt = diameters[np.where(diameters>10)[0]]
diameters_filt *= pixel_size

bin_edges = np.arange(
    np.floor(min(diameters_filt)), 
    np.ceil(max(diameters_filt)) + HIST_BIN_WIDTH, 
    HIST_BIN_WIDTH  # Set step size to 0.5 for bin width of 0.5
)
# Create histogram with fixed bin width of 1
ax1.hist(diameters_filt, bins=bin_edges, density=True, alpha=0.7, edgecolor='black')
ax1.set_xlabel(f'Equivalent Diameter ({pixel_unit})')
ax1.set_ylabel('Density')
title = f'Particle Diameters, {pixel_size} {pixel_unit}/pixel'
if has_temp:
    title += f', {temp_C} dC'
ax1.set_title(title)

ax1.grid(True)
ax1.set_aspect('auto')  # Changed from 'equal' to 'auto' for better visualization
fig1.tight_layout()

# Don't show it, but render the canvas
# Then get the rendering as numpy array
fig1.canvas.draw()
X = np.array(fig1.canvas.renderer._renderer)
# The array is (Y,X,C) with C being the color channel
# Get individual colors
R = X[:,:,0]
G = X[:,:,1]
B = X[:,:,2]

# Convert this to a greyscale image simple array and show as DM image
Mono = 0.2989*R + 0.5870*G + 0.1140*B 
DM.CreateImage( Mono ).ShowImage()

print("\nPython analysis complete")