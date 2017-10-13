## AugmentKit

ARKit, released by Apple, is an amazing foundation for building AR apps. AugmentKit is built on top of ARKit and provides additional tools for app developers such as Core Location integration and the ability to serialize and transfer 3D models (used as anchors in augmented reality) over the wire. AugmentKit uses the Metal flavor or ARKit and provides it's own 3D model renderer which eliminates the dependancy on SceneKit for most AR apps.

#### AugmentKit vs ARKit

ARKit provides three ways to interact with it. You can use SpriteKit, an unattractive choice for most because SpriteKit is a 2D game engine and AR is fundamentally a 3D technology. The second option is SceneKit, a full 3D game engine, which makes it the most convenient choice for ARKit integration. Finally, the last option is Metal, the most powerful and flexible option, but it is also the most difficult to learn and use. 

If you are developing a game, and especially if you already have some knowledge of SceneKit, you probably have enough tools with Apple's frameworks to reach your goals. But if you are an app developer,  and the idea of including a game engine in your project doesn't seem that attractive, AugmentKit may be for you. AugmentKit seeks to be as easy to implement and light weight.

Another feature that AugmentKit will provide is integrating more contextual awareness into ARKit. ARKit just deals with tracking the _relative_ position of objects (anchors) in 3D space. But chances are that more sophisticated AR apps are want to integrate things like location awareness and compass direction so that two people running two instances of the app will be able to see and share the same objects, or somebody can 'save' and object in world space and come back to see it days later.

#### Pre-Release

This project is currently on phase 2 (see goals below)

#### Features

* Written in Swift, ARKit, and Metal 2

#### Requirements

* A8 or higher iOS devices
* iOS 11.0 or higher
* Cameras require 60fps support
* Xcode 9 or higher to build

#### Project Goals

1. Use ARKit and Metal for plane detection and anchor tracking. Load and render complex models from ModelIO to use as anchors
2. Integrate with CoreLocation and CoreMotion to provide macro (meter scale) absolute location tracking in world space and micro (centemeter scale) relative anchor location tracking.
3. Ability to serialize, store, transmit, and load anchors in world space.

### History

The original goal of this project was to provide a general framework for building Augmented Reality apps. But Apple announced ARKit for iOS 11 which not only satisfies the original goal of this project, it will certainly do it better. So the projects goal changed. What's left of the original project is in the Pre-ARKit branch.

#### LICENSE
MIT
