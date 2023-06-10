from PIL import Image, ImageOps
from math import pi
import numpy as np

def speckle_image(image_size, speckle_size):
    """ 
    This code is an adaptation of Gudmun Slettemoens Matlab script. The method is described in: 
    http://pdxscholar.library.pdx.edu/cgi/viewcontent.cgi?article=1119&context=ece_fac
    """
    L = image_size                      #Image length
    D = L / specle_size                 #Diameter
    R = int(D/2)                        #Radius
    pad = int(L/2)                      #Padding
    speckle_img = np.zeros((L, L))

    # Generating random exponential noise in a circle in the image.
    # The speckle size is decided by the diameter. The smallest speckles give D = L/2.
    for i in range(pad - R ,pad + R):
        for j in range(pad - R, pad + R):
            if np.abs((pad-i)*(pad-i) + (pad-j)*(pad-j)) < D*D/4:
                speckle_img[i, j] = np.exp(np.random.uniform(-pi, pi))

    #Performing an FFT and removing imaginary numbers. This results in a speckle pattern.
    speckle_img = np.fft.fft2(speckle_img)
    speckle_img = np.multiply(speckle_img, np.conjugate(speckle_img))

    #PIL Image does not like complex values(Even if i = zero).
    speckle_img = np.abs(speckle_img)   

    #The dynamic range is too large. Need to change the contrast.
    mean = np.sum(speckleImg)/(L**2)          
    speckleImg = speckleImg * (1/sqrt(mean))          

    img_out = Image.fromarray(speckle_img)
    img_out.save('speckle.webp', lossless = True) 

def xcorr(img1, img2):
    """
    Cross-correlation function. Accepts two images.
    Returns correlation strength and offset. 
    """

    #Transforms the images to the frequency domain.
    img1_f = np.fft.fft2(img1)
    img2_f = np.fft.fft2(img2)

    #Correlation multiplication
    R = np.multiply(img1_f, np.conj(img2_f))

    #Transforms back to the spatial domain. 
    r = np.fft.ifft2(R)

    #Get offset and correlation strength
    x, y = np.unravel_index(np.argmax(r), r.shape)
    cc_strength = np.max(np.abs(r))

    #Change reference point to get offset vector
    if x > r.shape[0]/2 - 1:
      x = x - r.shape[0]
    if y > r.shape[1]/2 - 1:
      y = y - r.shape[1]

    return x, y, cc_strength


def partial_xcorr(img1, img2, res_fac=96):
    """
    Partial cross-correlation function. Accepts two images and resolution factor.
    Returns correlation strength and offset. 
    """

    #Transforms the images to the frequency domain.
    img1_f = np.fft.fft2(img1)
    img2_f = np.fft.fft2(img2)

    #Correlation multiplication
    Rx = np.multiply(img1_f[:,res_fac], np.conj(img2_f[:,res_fac]))
    Ry = np.multiply(img1_f[res_fac,:], np.conj(img2_f[res_fac,:]))

    #Transforms back to the spatial domain. 
    rx = np.fft.ifft(R)
    ry = np.fft.ifft(R)

    #Get offset and correlation strength
    x = np.argmax(rx)
    y = np.argmax(ry)
    cc_strength = np.max(np.abs(rx) + np.abs(ry))

    #Change reference point to get offset vector
    if x > rx.shape[0]/2 - 1:
      x = x - rx.shape[0]
    if y > ry.shape[0]/2 - 1:
      y = y - ry.shape[0]

    return x, y, cc_strength

