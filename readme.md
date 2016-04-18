## AugmentKit

This project is an iOS Framework which uses the GPU to perform image processing of real-time video. Eventually this framework will evolve into an augmented reality framework.

#### Features

* Flexible processing pipeline written using Swift and Metal
	* Can apply separate color and image filters
	* Can apply the following color filters:
	  * Full color
	  * Grayscale
	  * Protonopia simulation
	  * Deuteranopia simulation
	  * Tritanopia simulation
	* Can apply the following image processing filters:
	  * No filter
	  * Raw Sobel filter
	  * Composite Sobel filter (overlays on video)
	  * Raw Canny filter
	  * Composite Canny filter (overlays on video)
	  * Comic filter (experimental, cartoon shading)
	  * Protanopia correction (Daltonization)
	  * Deuteranopia correction (Daltonization)
	  * Tritanopia correction (Daltonization)
	* Can additionally invert the resulting video
	* Uses either a separable gaussian blur or a high-quality [linear sampled gaussian blur](http://rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/) for noise reduction.

#### Requirements

* A7 or A8 iOS device (iPhone 5s+, iPad Air+, iPad Mini 2+)
* iOS 8.0 or higher
* Cameras require 60fps support
* Xcode 6.1 or higher to build

#### Algorithms Used

* [Canny edge detectors](http://en.wikipedia.org/wiki/Canny_edge_detector) as the primary edge detector and as a first pass for the Sobel operator
* [Sobel operator](http://en.wikipedia.org/wiki/Sobel_operator) for an advanced edge detector
* [Daltonization](http://www.daltonize.org/search/label/Daltonize) for colorblindness simulation and correction im/Gaussian_blur) as a pre-pass to reduce noise in the images
