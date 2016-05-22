## AugmentKit

This project is an iOS Framework which uses the GPU to perform real-time image processing from the camera. Eventually this framework will evolve into an augmented reality framework.

#### Pre-Release

This project is currently on phase 1 (see goals below)

#### Features

* Written in Swift and Metal
* Able to specify a pipeline including render, compute, and Metal Performance shaders with a plist
	* Current shaders include
		* Sobel (Metal Performance shader)
		* Sobel (fragment shader)
		* Canny (fragment shader)
		* GaussianBlur (Metal Performance shader)
		* Blur (fragment shader)
		* Hough Transform (fragment shader)

#### Requirements

* A7 or A8 iOS device (iPhone 5s+, iPad Air+, iPad Mini 2+)
* iOS 8.0 or higher
* Cameras require 60fps support
* Xcode 6.1 or higher to build

#### Project Goals

1. Use edge detection and a Hough transform implementation to detect lines and vanising points
2. Use lines and vanishing points along with camera sensor data to estimate size and position of cuboids in real space
3. A caching mechanism that loads and saves real space cuboids with location data. 
