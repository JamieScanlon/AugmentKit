## AugmentKit

ARKit, released by Apple, is an amazing foundation for building AR apps. AugmentKit is built on top of ARKit and provides additional tools for app developers building augmented reality apps. AugmentKit uses the Metal flavor or ARKit and provides it's own physically based render (PBR) engine which eliminates the dependancy on SceneKit for most AR apps and is tailored for rendering AR. 

#### AugmentKit vs ARKit

Apple's ARKit provides three ways to create augmented reality apps. You can use SpriteKit, an unattractive choice for most because SpriteKit is a 2D game and render engine and AR is fundamentally a 3D technology. The second option is SceneKit, a full 3D renderer and game engine. And finally Metal, the most powerful and flexible option, but it is also the most difficult to learn and use. 

If you are developing a game, or is you have a significant investment in using SceneKit, you probably have enough tools with Apple's frameworks to reach your goals. Unfortunately SceneKit is a large, general purpose, game and render engine that not only adds complexity, but is often times overkill for most AR apps that just want to render a few models, not entire worlds. If you are an app developer, you may not be interested in immersing your self in the game development techniques in order to build an app, and this is the problem AugmentKit wants to solve. AugmentKit seeks to be an easy to implement and light weight alrenative to using SceneKit for developing AR apps.

Along with being simple and light weight, AugmentKit provides more contextual awareness into ARKit. ARKit just deals with tracking the _relative_ position of objects (anchors) in 3D space. But chances are that more sophisticated AR apps are want to integrate things like location awareness and compass direction so that two people running two instances of the app will be able to see and share the same objects, or somebody can 'save' and object in world space and come back to see it days later.

### What Can AugmentKit Do?

##### Location based anchors

##### Direction and surface detection

![](media/AugmentKit-Sample-2.gif)

##### Tracking anchors

##### Paths

![](media/AugmentKit-Sample-3.gif)

##### UIView anchors

##### Custom PBR render engine

![](media/AugmentKit-Sample-1.gif)

### Getting Started

#### Creating the AR World

Begin by creating an AKWorld object and provide it with a configuation and an MTKView to render to.

```swift
let worldConfiguration = AKWorldConfiguration()
let world = AKWorld(renderDestination: view, configuration: worldConfiguration)
```

Make sure the orientation of the device is set.

```swift
world.renderer.orientation = UIApplication.shared.statusBarOrientation
```

Initialize the AR session and begin AR tracking

```swift
world.initialize()
world.begin()
```

#### Adding an anchor

Now the AugmentKit world is up an running but there's not much to see yet. The fun comes from placing augmented reality objects in the world. The following code could be put in a tap gesture handler. For instance, here's how to add a new MDLAsset to the world at the devices current location.

```swift
let anchorModel = MDLAssetTools.asset(named: "retrotv.usdz", inBundle: Bundle.main)!
let currentWorldLocation = world.currentWorldLocation
let newObject = AugmentedObject(withModelAsset: anchorModel, at: currentWorldLocation)
world.add(anchor: newObject)
```

#### Adding a compass that follows you

Trackers are different from anchors in that they are not anchored to a fixed point in the world, they track the movement of another object. Here's an example of a tracker that follows at your feet and always points north. Your own personal compass. 

```swift
if let asset = MDLAssetTools.assetFromImage(inBundle: Bundle.main, withName: "compass_512.png") {
    // Position it 3 meters down from the camera
    let offsetTransform = matrix_identity_float4x4.translate(x: 0, y: -3, z: 0)
    let userTracker = UserTracker(withModelAsset: asset, withUserRelativeTransform: offsetTransform)
    userTracker.position.heading = WorldHeading(withWorld: myWorld, worldHeadingType: .north(0))
    world.add(tracker: userTracker)
}
```

#### Adding a target where you look

Targets are objects that appear at the intersection of a line (vector really) and something else like a plane that ARKit has detected. In this example, the vector points straight out from the device and wherever it intersects the first plane, a target is drawn. It also puts a pulsing effect on the gaze target so it appears like an interactive cursor.

```swift
if let asset = MDLAssetTools.assetFromImage(inBundle: Bundle.main, withName: "Gaze_Target.png", extension: "", scale: 0.2) {
    let gazeTarget = GazeTarget(withModelAsset: asset, withUserRelativeTransform: matrix_identity_float4x4)
    let alphaEffect = PulsingAlphaEffect(minValue: 0.2, maxValue: 1)
    gazeTarget.effects = [AnyEffect(alphaEffect)]
    world.add(gazeTarget: gazeTarget)
}
```

#### Adding a path

Paths are line segments that are drawn between anchors. Here's an example that draws a path that loops around the circular spaceship building in Apple Park. This also demonstrates how anchors can be added with a fixed latitude and longitude instead of relative to your current position as in the previous example.

```swift
guard let location1 = world.worldLocation(withLatitude: 37.3335, longitude: -122.0106, elevation: currentWorldLocation.elevation) else {
    return
}

guard let location2 = world.worldLocation(withLatitude: 37.3349, longitude: -122.0113, elevation: currentWorldLocation.elevation) else {
    return
}

guard let location3 = world.worldLocation(withLatitude: 37.3362, longitude: -122.0106, elevation: currentWorldLocation.elevation) else {
    return
}

guard let location4 = world.worldLocation(withLatitude: 37.3367, longitude: -122.0090, elevation: currentWorldLocation.elevation) else {
    return
}

guard let location5 = world.worldLocation(withLatitude: 37.3365, longitude: -122.0079, elevation: currentWorldLocation.elevation) else {
    return
}

guard let location6 = world.worldLocation(withLatitude: 37.3358, longitude: -122.0070, elevation: currentWorldLocation.elevation) else {
    return
}

guard let location7 = world.worldLocation(withLatitude: 37.3348, longitude: -122.0067, elevation: currentWorldLocation.elevation) else {
    return
}

guard let location8 = world.worldLocation(withLatitude: 37.3336, longitude: -122.0074, elevation: currentWorldLocation.elevation) else {
    return
}

guard let location9 = world.worldLocation(withLatitude: 37.3330, longitude: -122.0090, elevation: currentWorldLocation.elevation) else {
    return
}

let path = PathAnchor(withWorldLocaitons: [location1, location2, location3, location4, location5, location6, location7, location8, location9, location1], color: .red)
world.add(akPath: path)
```

#### Rendering a UIView in the AR world

Any UIView can be rendered as a surface in the AR world. In this example, we will render a UITextView containing a paragraph of text. We will also use a special heading that makes sure the surface always faces you wherever you go

```swift
let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
textView.font = UIFont(descriptor: .preferredFontDescriptor(withTextStyle: .body), size: 14)
textView.textColor = UIColor(red: 200/255, green: 109/255, blue: 215/255, alpha: 1)
textView.text = """
A way out west there was a fella,
fella I want to tell you about, fella
by the name of Jeff Lebowski. At
least, that was the handle his lovin'
parents gave him, but he never had
much use for it himself. This
Lebowski, he called himself the Dude.
Now, Dude, that's a name no one would
self-apply where I come from. But
then, there was a lot about the Dude
that didn't make a whole lot of sense
to me. And a lot about where he
lived, like- wise. But then again,
maybe that's why I found the place
s'durned innarestin'...
"""
textView.backgroundColor = .clear
let location = world.worldLocationWithDistanceFromMe(metersAbove: 0, metersInFront: 2)!
let heading = AlwaysFacingMeHeading(withWorldLocaiton: location)
let viewSurface = AugmentedUIViewSurface(withView: textView, at: location, heading: heading)
world.add(anchor: viewSurface)
```

### More Documntation

[Full Documentation](http://htmlpreview.github.com/?https://github.com/JamieScanlon/AugmentKit/blob/master/docs/index.html)

#### Basic Concepts

##### The AR World

The AR world is a layer on top of the real world that you view through the window of the divice running AugmentKit. Everything in the real world exists in the AR world but not necessarily the opposite. In the real world we can specify a concrete location with latitude, longitude and elevation. In the AR world we specify location as distance in the x, y, and z direction from a origin. The origin is arbitrary and is decided when you start an AR session. One of the core responsibilitied of AugmentKit is to tie the arbitrary origin of the AR world to a concrete location in the real world thereby making the locations in the AR world concrete.

##### Real vs. Augmented

AugmentKit tracks objects in the real world as well as the AR world. The most simplest of these is surfaces. Real objects in AugmentKit can be manipulated to some degree, for instance you could turn a wall into a tv screen, but the geometry and positioning of real objects are not controled by AugmentKit. Augmented objects, on the other hand, only exist in the AR world and therefore can be fully manipulated by AugmentKit.

##### Anchors, Trackers, and Targets

There are three basic types of objects in the ARWorld, Anchors, Tracker, and Targets. Any of them can be real or augmented. Anchors are objects that are _fixed_ to a location. An anchor is like a place on a map and does not move. Trackers are objects with a _relative_ location. The location is relative to another object or location. Trackers can move. One ware is by changing their relative location, for example a car moving down the street is a Tracker because it's position is relative to the AR World origin but it's position is changing as the car is moving. The other way Trackers can move is if their relative position is fixed but it's fixed to another moving Tracker, for example a bike mounted to the bike rack of the car. Targets are like Trackers in that they can move, but are slightly different. A Target is an object that is positioned at the intersection of a vector and another object, usually a real surface. The best way to think of Targets is like a the dot of a laser pointer. The laser pointer points in a arbitrary direction (the vector) and where the laser intersects with something else, like a screen. In this example the Target would be the dot of the laser pointer but in the AR World it doesn't have to be a dot, it could be any geometry.

#### Key Classes and Protocols

##### AKWorld

The AKWorld manages the metal renderer, the ARKit engine, and the world state and is the primary way you interact with AugmentKit. When setting up the AKWorld, you provide a configuration object which determines things like weather Location Services are enabled and what the maximum render distance is. As well as being the primary way to add Anchors, Trackers, Targets and Paths, the AKWorld instance also provides state information like the current world locaiton and utility methods for determining the world location based on latitude and longitude. AKWorld also provides some dubuging tools like logging and being able to turn on visualizations of the surfaces and raw tracking points that ARKit is detecting.

##### AKWorldLocation

AKWorldLocation is a protocol that ties together a position in the AR world with a locaiton in the real world. When the ARKit session starts up, it crates an arbitrary coordinate system where the origin is where the device was located at the time of initialization. Every device and every AR session, therefore, has it's own local coordinate system. In order to reason about how the coordinate system relates to actual locations in the real world, AugmentKit uses location services to map a point in the ARKit coordinate system to a latitude and longitude in the real world and stores this as a AKWorldLocation instance. Once a reliable AKWorldLocation is found, other AKWorldLocation objects can be derived by calculating their relative distance from the one reliable reference AKWorldLocation object.

The WorldLocation and GroundFixedWorldLocation are two concrete implementations of this protocol.

##### AugmentedObject

AugmentedObject is a general purpose Anchor class that can be rendered in the AKWorld. As the name implies, it is an augmented object so it does not exist in the real world and it is rendered at a fixed location.

##### UserTracker

UserTracker is a Tracker that is position relative to the users current location and therefore follows the user. This is a useful class for rendering objects that the user always sees such as UI controls or information.

##### GazeTarget

GazeTarget is a special Target object where it's position is th users position and the direction vector is where the user (or device) is looking. In other words it tracks the users gaze. This is a convenient class for implementing a pointer control that can be used to interact with objects in the AR world. You could, for example, inplement a pointer so that when a user presses and holds while pointing to an object, the user can move and rearange the object.

##### PathAnchor

A path in AugmentKit is a special type of augmented anchor. It is a anchor that contains a collection of anchors. Each sub-anchor is the termination of a line segment and the collection is a multi-segment path. By providing the locations of the segment end points, a PathAnchor creates a collection of anchors and renders the line as if playing conenct to dots. 

##### AugmentedUIViewSurface

AugmentedUIViewSurface is an augmented anchor with the geometry of a plane or surface. On to this surface is drawn the contents of ant UIView. In this way it can be thought of as a AR screen that you can build just like you build any screen in UIKit. An because AugmentKit does not have it's own text rendering engine, this is also the best way to render text in the AR world. Anything you can do in a UIView, you can render in the AR world. Animation is not supported yet but will be soon.

### Alpha-Release

This project is in Alpha having completed all of the base pre-release functionality. There are _plenty_ of bugs and untested areas especially around improving the renderer to reliably support and render a broad variety of models (currently it's only been tested with a few types of SceneKit models). Also animation is theoretically supported but untested. AugmentedUIViewSurface (a way to render arbitrary UIView's in the AR world) has the potential to unlock some powerful capabilities but needs to support real-time rendered animation to be considered done. More can be done to improve jerky rendering by smoothing out the raw positioning that ARKit spits out. Surface culling (having AR objects apear to go behind objects that are in front of them) would be a huge win but this is relatively unexplored territory. Also the long term goal is to continue to develop the render engine and break it off into a separate project that would hopefully be the first, production-ready, open-source PBR render engine based in Metal. This project will be called Candelabra and will aim to be an open source alternative to using the SceneKit render engine. By doing this I hope to make it easier for developers interested in Metal to find a good source of production-ready code that can be learned from and extended.

### Features

* Written in Swift 5, ARKit 2, and Metal 2

### Requirements

* A8 or higher iOS devices
* iOS 12.0 or higher
* Cameras require 60fps support
* Xcode 10 or higher to build

### Goals

#### Pre-Release Project Goals

- [x] Use ARKit and Metal for plane detection and anchor tracking. Load and render complex models from ModelIO to use as anchors
- [x] Integrate with CoreLocation to provide the ability to tie a point (3D transform) in AR space to a point (latitude, longitude, elevation) in real world space.
- [x] Ability to serialize, store, transmit, and load anchors (including 3D meshes) in world space.
- [x] More primatives, including tracking anchors that follow users, and paths that can be used to draw line paths in 3D world space.

#### Alpha-Release Project Goals

- [x] Remove and Update methods for augmented objects
- [x] Refinements to UIControls and interactions including exposing tap and other gestures, smoothing
- [x] Mechanism for surfacing the state of the world and the renderer so it can be surfaced to the user
- [x] Mechanism for surfacing errors
- [x] Test and fix animation for models
- [x] Test and fix a variety of models.
- [x] Support per-instance models

#### Beta-Release Project Goals
- [x] Test and fix animation for models
- [x] Animated AugmentedUIViewSurface
- [ ] Improve jerky movements with smoothing
- [ ] Surface culling
- [x] Offload many per-frame calculations to GPU Kernel function
- [x] Improve render engine
- [x] Add support for shadow maps

#### _Stretch Goals_

* Use veritcal plane detection to achieve a spacial fingerprint of the local area.
* Ability to serialize, store, transmit and load spacial fingerprints and associate them to anchors in order to achieve another way in which the real world can be locked to the AR world.

### History

The original goal of this project was to provide a general framework for building Augmented Reality apps. But Apple announced ARKit for iOS 11 which not only satisfies the original goal of this project, it will certainly do it better. So the projects goal changed. What's left of the original project is in the Pre-ARKit branch.

### LICENSE
MIT
