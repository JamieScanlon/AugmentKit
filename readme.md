## AugmentKit

### Updated: June, 2017

The original goal of this project was to provide a general framework for building Augmented Reality apps. But Apple announced ARKit for iOS 11 which not only satisfies the original goal of this project, it will certainly do it better. So I'm changing this projects goal!

#### AugmentKit vs ARKit

ARKit, released by Apple, is an amazing foundation for building AR apps. AugmentKit will be built on top of ARKit and provide additional  tools for app developers.

ARKit provides three ways to interact with it. You can use SpriteKit, an unattractive choice for most because SpriteKit is a 2D gme engine and AR is fundamentally a 3D technology. The second option is SceneKit which is a full 3D game engine wich makes it a natural choice for ARKit integration. If you are developing a game, and especially if you already have someknowledge of SceneKit, you probably have enough tools with Apples frameworks to reach your goals. The last option is Metal and it is kindof the 'everything else' option. Metal provides low level access to the GPU which means that if it can be done, Metal can do it.

The problem is that none of these are particularly great options for app developers. Two out of the three frameworks are geared toward games, and the other requires so much setup, configuration, and knowledge about GPU architecture that it's too cumbersome for the average developer. AugmetKit is attempting to solve this problem by providing a framework geared towawrd app developers that is higer level than Metal. AugmetKit is based on the Metal flavor of ARKit and will integrate with ModelIO to provide a way to load in models to use as anchors.

Another feature that AugmentKit will provide is integrating more contextual awareness into ARKit. ARKit just deals with tracking the _relative_ position of objects (anchors) in 3D space. But chances are that more sophisticated AR apps are want to integrate things like location awareness and compass direction so that two people running two instances of the app will be able to see and share the same objects, or somebody can 'save' and object in world space and come back to see it days later.

#### Pre-Release

This project is currently on phase 1 (see goals below)

#### Features

* Written in Swift, ARKit, and Metal

#### Requirements

* A8 or higher iOS devices
* iOS 11.0 or higher
* Cameras require 60fps support
* Xcode 9 or higher to build

#### Project Goals

1. Use ARKit and Metal for plane detection and anchor tracking. Load and render complex models from ModelIO to use as anchors
2. Integrate with CoreLocation and CoreMotion to provide macro (meter scale) absolute location tracking in world space and micro (centemeter scale) relative anchor location tracking.
3. Ability to serialize, store, transmit, and load anchors in world space.

#### LICENSE
MIT
