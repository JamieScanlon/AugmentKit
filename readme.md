## AugmentKit

This project is an iOS Framework which uses the GPU to perform real-time image processing from the camera. Eventually this framework will evolve into an augmented reality framework.

#### Features

* Written in Swift and Metal
* Able to specify a pipeline including render, compute, and Metal Performance shaders with a plist
	* Current shaders include
		* Sobel (Metal Performance shader)
		* Sobel (fragment shader)
		* Canny (fragment shader)
		* GaussianBlur (Metal Performance shader)
		* Blur (fragment shader)

#### Requirements

* A7 or A8 iOS device (iPhone 5s+, iPad Air+, iPad Mini 2+)
* iOS 8.0 or higher
* Cameras require 60fps support
* Xcode 6.1 or higher to build
