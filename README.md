<a href="https://github.com/konovod/myecs/actions/workflows/ci.yml">
      <img src="https://github.com/konovod/myecs/actions/workflows/ci.yml/badge.svg" alt="Build Status">
</a>

# MyECS

##### Table of Contents  
* [Introduction](#introduction)
* [Main parts of ecs](#main-parts-of-ecs)
  * [Entity](#entity)
  * [Component](#component)
  * [System](#system)
* [Special components](#special-components)
  * [ECS::SingleFrame](#ecssingleframe)
  * [ECS::Multiple](#ecsmultiple)
  * [ECS::Singleton](#ecssingleton)
* [Other classes](#other-classes)
  * [ECS::World](#ecsworld)
  * [ECS::Filter](#ecsfilter)
  * [ECS::Systems](#ecssystems)
* [Engine integration](#engine-integration)
* [Other features](#other-features)
  * [Statistics](#statistics)
  * [Iterating without filter](#iterating-without-filter)
  * [Callbacks](#callbacks)
* [Benchmarks](#benchmarks)
* [Serialization](#serialization)
  * [Binary](#binary)
  * [YAML](#yaml)
* [Plans](#plans)
* [Contributors](#contributors)
## Introduction

You can add shard as a dependency to your application's `shard.yml`:
```yaml
dependencies:
  myecs:
    github: konovod/myecs
```
Alternativale, you can just copy file `src/myecs.cr` to your sources as it's single-file library.

Then do 
```crystal
require "myecs"
``` 
And then use it:
```crystal
# declare components
record Position < ECS::Component, x : Int32, y : Int32
record Velocity < ECS::Component, vx : Int32, vy : Int32

# declare systems
class UpdatePositionSystem < ECS::System
  def filter(world)
    world.all_of([Position, Velocity])
  end

  def process(entity)
    pos = entity.getPosition
    speed = entity.getVelocity
    entity.update(Position.new(pos.x + speed.x, pos.y + speed.y))
  end
end

# create world
world = ECS::World.new

# create entities
5.times { world.new_entity.add(Position.new(10, 10)) }
10.times do
  ent = world.new_entity
  ent.add(Position.new(1, 1))
  ent.add(Velocity.new(1, 1))
end

# create systems
systems = ECS::Systems.new(world)
systems.add(UpdatePositionSystem)

# run systems
systems.init
10.times do
  systems.execute
end
systems.teardown
```

## Main parts of ecs

### Entity
Сontainer for components. Consists from UInt64 and pointer to `World`:
```crystal
struct Entity
  getter id : EntityID
  getter world : World
    ...
```

```crystal
# Creates new entity in world context. 
# Basically just allocates a new identifier so it's fast.
entity = world.new_entity

# destroying entity marks entity id as free so it can be reused. It is also destroyed when last component removed from it.
# If you need to hold an empty entity, suggested way is to add some component to it.
entity.destroy
```

### Component
Container for user data without / with small logic inside. Based on Crystal struct's:
```crystal
record Comp1 < ECS::Component,
  x : Int32,
  y : Int32,
  name : String
```
Components can be added, requested, removed:
```crystal
entity = world.new_entity
entity.add(Comp1.new(0, 0, "name"))
# method is autogenerated from component class name. 
# Will raise if component isn't present
comp1 = entity.getComp1  
comp2 = entity.getComp2? # will return nil if component isn't present
entity.remove(Comp1)

# basically shortcut for deleting one component and adding another.
entity.replace(Comp1, Comp2.new) 
```

They can be updated (changed) using several ways:
```crystal
entity = world.new_entity
entity.add(Comp1.new(0, 0, "name"))

# Replace Comp1 with another instance of Comp1. 
# Will raise if component isn't present
entity.update(Comp1.new(1, 1, "name1")) 

entity.set(Comp1.new(2, 2, "name2")) # Adds Comp1 or replace it if already present

# autogenerated method, returns Pointer(Comp1), so you can access it directly
# this is not a recommended way to work with Crystal structs
# but can provide maximum performance
ptr = entity.getComp1_ptr 
ptr.value.x = 5
# important - after deleting component in a pool would be reused
# so don't save a pointer if you are not sure that component won't be deleted
```

### System
Сontainer for logic for processing filtered entities. 
User class can implement `init`, `execute`, `teardown`, `filter`, `preprocess` and `process` (in any combination. Just skip methods you don't need).
```crystal
class UserSystem < ECS::System
  # @world : ECS::World - world
  # @active : Bool - allows to temporary enable or disable system

  def initialize(@world : ECS::World)
    super(@world) # constructor should pass @world field
  end

  def init
    # Will be called once during ECS::Systems.init call
  end

  def preprocess
    # Will be called on each ECS::Systems.execute call, before `#process` and `#execute`
  end

  def filter(world)
    # Called once during ECS::Systems.init, after #init call.
    # If this method present, it should return a filter that will be applied to a world
    world.of(SomeComponent)
  end

  def process(entity)
    # will be called during each ECS::Systems.execute call, before #execute, 
    # for each entity that match the #filter
  end

  def execute
    # Will be called on each ECS::Systems.execute call
  end

  def teardown
    # Will be called once during ECS::Systems.teardown call
  end

end
```

### Special components
#### ECS::SingleFrame
annotation `@[ECS::SingleFrame]` is for components that have to live 1 frame (usually - events). The main difference is that they are supposed to be deleted at once, so their storage can be simplified (no need to track free indexes). They should be deleted by adding `ECS::RemoveAllOf` system in a right place of systems list (or just using `.remove_singleframe(T)`).

```crystal
require "./src/myecs"

@[ECS::Multiple]
@[ECS::SingleFrame]
record SomeRequest < ECS::Component, data : String

class ExecuteSomeRequestsSystem < ECS::System
  def filter(world)
    world.of(SomeRequest)
  end

  def process(ent)
    req = ent.getSomeRequest
    puts "request #{req.data} called for #{ent}"
  end
end

world = ECS::World.new
systems = ECS::Systems.new(world)
  .add(ExecuteSomeRequestsSystem)
  .remove_singleframe(SomeRequest) # shortcut for `add(ECS::RemoveAllOf.new(@world, SomeRequest))`
systems.init
# now you can add SomeRequest to the entity
world.new_entity.add(SomeRequest.new("First")).add(SomeRequest.new("Second"))
systems.execute
```

In case you tend to forget about removing such single-frame components, ECS checks it for you - if a single-frame component is created, but no corresponding `RemoveAllOf` is present in systems list, runtime exception will be raised

```crystal
@[ECS::SingleFrame]
record SomeEvent < ECS::Component

world = ECS::World.new
systems = ECS::Systems.new(world)
# ...some systems added
systems.init
systens.execute #this won't raise - maybe we don't need SomeEvent at all
world.new_entity.add(SomeEvent.new) # raises
```

In a rare cases when you need to override this check, you can use `@[ECS::SingleFrame(check: false)]` form:
```crystal
@[ECS::SingleFrame(check: false)]
record SomeEvent < ECS::Component

world = ECS::World.new
systems = ECS::Systems.new(world)
# ...
world.new_entity.add(SomeEvent.new) # this won't raise
```

#### ECS::Multiple
Note above example also shows the use of `@[ECS::Multiple]`. This is for components that can be added multiple times. They have some limitations though - filters can't iterate over more then one type of components with this annotation (as this would usually mean cartesian product, unlikely needed in practice), there is no way to get multiple components outside of filter (it is planned though, but it won't be efficient nor cache-friendly), `remove` deletes all of components on target entity and there is no way to delete only one.
`ECS::Multiple` can be combined with `ECS::SingleFrame` but that's not a requirement - there are perfectly correct use cases for `ECS::Multiple` on persistent components - add several sprites to one renderable object or add several weapons to a tank. The only thing is that with current API you won't be able to remove single weapon in that case - only remove all of them. So if you need better control over components just use good old "add an entity with single component and link it to parent entity" approach.

#### ECS::Singleton
annotation `@[ECS::Singleton]` is for data sharing. It creates component that is considered present on every entity (iteration on it isn't possible though). So you can do

```crystal
@[ECS::Singleton]
record Config < ECS::Component, values : Hash(String, Int32)

class InitConfigSystem < ECS::System
  def init
    config = ...some config initialization
    @world.new_entity.add(Config.new(config))

    # another way
    @world.add(Config.new(config)) unless @world.component_exists?(Config)
  end
end

class SomeAnotherSystem < ECS::System
  def execute
    config = @world.new_entity.getConfig.values # gets the same values

    # another way
    config = @world.getConfig.values
  end
end
```

### Other classes

#### ECS::World
Root level container for all entities / components, is iterated with ECS::Systems:
```crystal
world = ECS::World.new

# you can delete all entities
world.delete_all

# also delete all entities, but calls `when_removed` callbacks (slower)
world.delete_all(with_callbacks: true)

# you can create entity
entity = world.new_entity

# you can iterate all entities
world.each_entity do |entity|
  puts entity.id
end

# you can create filters
world.any_of([Comp1, Comp2]).any_of([Comp3, Comp4])
```

#### ECS::Filter
Allows to iterate over entities with specified conditions.
Created by call `world.new_filter` or just by adding any conditions to `world`.

Filters that is possible:
  - `any_of([Comp1, Comp2])`: at least one of the components must be present on entity
  - `all_of([Comp1, Comp2])`: all of the components must be present on entity
  - `of(Comp1)`: alias for `all_of([Comp1])`
  - `exclude([Comp1])`: none of the components could be present on entity
  - `filter{|ent| some_check(ent) }`: user-provided filter procedure, that must return true for entity to be passed.

All of them can be called 0, 1, or many times using method chaining. 
So `any_of([Comp1, Comp2]).any_of([Comp3, Comp4])` means that either Comp1 or Comp2 should be present AND either Comp3 or Comp4 should be present.

`ECS::Filter` includes `Enumerable(Entity)`, so you can use methods like `#any?` or `#count`. 
Note that `#select` in `Enumerable` returns an array, not a `ECS::Filter`. To create a filter use `#filter` method.

#### ECS::Systems
Group of systems to process `EcsWorld` instance:
```crystal
world = ECS::World.new
systems = ECS::Systems.new(world)

systems
  .add(MySystem1.new(world))
  .add(MySystem2) # shortcut for add(MySystem2.new(systems.@world))
  .add(MySystem3)

systems.init
loop do
  systems.execute
end
systems.teardown
```
You can add Systems to Systems to create hierarchy.
You can inherit from `ECS::Systems` to add systems automatically:
```crystal
class SampleSystem < ECS::Systems
  def initialize(@world)
    super
    add InitPlayerSystem
    # note that shortcut `add KeyReactSystem` isn't applicaple here because 
    # system require other params in initialize
    add KeyReactSystem.new(@world, pressed: CONFIG_PRESSED, down: CONFIG_DOWN)
    add ReactPlayerSystem
    add MovePlayerSystem
    add RotatePlayerSystem
    add StopRotatePlayerSystem
    add SyncPositionWithPhysicsSystem
    add DrawDebugSystem
  end
end
```
### Engine integration
huh, this is integration with my [nonoengine](https://gitlab.com/kipar/nonoengine):
(full project is available at https://github.com/konovod/nonoecs-template)
```crystal
# main app:
require "./ecs"
require "./basic_systems"
require "./physics_systems"
require "./demo_systems"

@[ECS::SingleFrame(check: false)]
struct QuitEvent < ECS::Component
end

world = ECS::World.new
systems = ECS::Systems.new(world)
  .add(BasicSystems)
  .add(PhysicSystems)
  .add(SampleSystem)

systems.init
loop do
  systems.execute
  break if world.component_exists? QuitEvent
end
systems.teardown

...
# basic_systems.cr:
require "./libnonoengine.cr"
require "./ecs"

class BasicSystems < ECS::Systems
  def initialize(@world)
    super
    add EngineSystem.new(world)
    # add RenderSystem.new(world)
    add ShouldQuitSystem.new(world)
  end
end

class EngineSystem < ECS::System
  def init
    Engine[Params::Antialias] = 4
    Engine[Params::VSync] = 1

    Engine.init "resources"
  end

  def execute
    Engine.process
  end
end

class ShouldQuitSystem < ECS::System
  def execute
    @world.new_entity.add(QuitEvent.new) if !Engine::Keys[Key::Quit].up?
  end
end

```

see `bench_ecs.cr` for some examples, and `spec` folder for some more. Proper documentation and examples are planned, but not soon.

## Other features
### Statistics
You can add `ECS.debug_stats` at he end of program to get information about number of different systems and component classes during compile-time. Userful mostly just for fun :)

you can get runtime statistics (how many components of each type is present) using `ECS::World#stats`. It returns with component name as a key and components count as value.
There is also non-allocating version of `stats` that yields an info instead of creating a hash:
```crystal
world = init_benchmark_world(1000000)

puts world.stats 
# {"Comp1" => 500000, "Comp2" => 333334, "Comp3" => 200000, "Comp4" => 142858, "Config" => 1}

# will print the same info
world.stats do |comp_name, value| 
  puts "#{comp_name}: #{value}" 
end
```


### Iterating without filter
Sometimes you just need to check if some component is present in a world. No need to create a filter for it - just use `world.component_exists?(SomeComponent)`

You can also iterate over single component without creating Filter using `world.query`.
It returns a lightweight `SimpleFilter` instance, that includes `Enumerable(Entity)`.
This could be useful when iterating inside `System#process`:
```crystal
class FindNearestTarget < ECS::System
  def filter(world)
    world.all_of([Pos, FindTarget])
  end

  def process(entity)
    pos = entity.getPos
    nearest = Nil
    nearest_range = INFINITY
    # world.of(IsATarget) will allocate a Filter, so you should create it at `initialize` and store it somewhere
    # so here is an easier way:
    world.query(IsATarget).each do |target|
      range = distance(target.getPos, pos)
      if nearest_range > range
        nearest = target
        nearest_range = range
      end
    end
    # ...
    # You can also use Enumerable utility methods:
    nearest = world.query(IsATarget).min_by { |target| distance(target.getPos, pos) }
  end
end
```

### Callbacks
If you define `when_added` method, it will be called every time after component was added to entity.
If you define `when_removed` method, it will be called every time before component is removed from entity (or entity is destroyed).
```crystal
record PhysicalBody < ECS::Component, raw : PhysEngine::Body do
  def when_removed(entity)
    raw.destroy
  end
end
```
This correctly process SingleFrame, Multiple and Singleton components. 
Note that by default `world.delete_all` won't call `when_removed` for performance purposes (and because it doesn't make sense in many cases).
Use `world.delete_all(with_callbacks: true)` if you need to still call `when_removed` for all components or use specialized filter to delete selected components before delete_all.

## Serialization

### Binary
`ECS::World` can be serialized to binary blob using brilliant [Cannon](https://github.com/Papierkorb/cannon) library. This done using `World#encode` and `World#decode`:

```crystal
  # saves world state to a file.
  save = File.open("./save", "wb")
  world.encode save
  save.close

  # loads world from a file
  save = File.open("./save", "rb")
  world = ECS::World.new
  begin
    world.decode save
  rescue ex : Exception
    error("Savefile is corrupt")
  ensure
    save.close
  end
```

Of course this is not limited to files, you can use any `IO` to pass it over network etc.

Note that `Cannon` library by design have no ways to check that data are correct, you have to implement it yourself.

Most components can be serialized automatically, but if it doesn't work - define `#to_cannon_io(io)` and `def self.from_cannon_io(io) : self` for a component.

### YAML

There is a also an experimental feature - serialize world to and from YAML format.

Example use case - loading of pregenerated entities.

```crystal
require "myecs"

# not required by default because not every app needs YAML support
require "myecs/yaml"

# Only compoonents inherited from `ECS::YAMLComponent` are serialized.
record ItemSlot < ECS::YAMLComponent, name : String
record CraftItem < ECS::YAMLComponent, name : String, slots : Array(ECS::Entity)
record CraftItemStats < ECS::YAMLComponent, cost : Int32, mass : Int32

...
File.open(filename) do |file|
  world = ECS::World.from_yaml(file)
end

puts world.to_yaml

# Another way is to add yaml data to existing world:
world.add_yaml(file)
```
Argument passed to deserialization can be either `IO` or `String`

Generated YAML will be a hash, each entry is a `ECS::Entity`.

Keys of hash are used to link to the entities (in case of `to_yaml` keys looks like `Entity1234` but that is not required).

Values are array of components on the entity, each component must have a `type` field that represents class of component.

Example file:
```YAML
---
  slot_energy: [{type: ItemSlot, name: "Power source"}]
  slot_radio: [{type: ItemSlot, name: "Radio antenna"}]
  slot_life: [{type: ItemSlot, name: "Life support"}]
  # note that we can link to any entity by its key
  item1: [{type: CraftItem, name: "Near space antenna", slots: [slot_radio]}, {type: CraftItemStats, cost: 100, mass: 100}]
  item2: [{type: CraftItem, name: "Lunar antenna", slots: [slot_radio]}, {type: CraftItemStats, cost: 200, mass: 200}]
```

It is possible to load yaml from multiple sources (e.g. to split "slots" and "items" in a code before). All sources will share the same entity keys, so entities from one source can link to another

```crystal
  world = ECS::World.from_yaml do |yaml|
    yaml.read source1
    yaml.read source2
  end
  
  # or add to existing world:
  world.add_yaml |yaml|
    yaml.read file1
    yaml.read string2
  end
```

### Difference
Binary and YAML serialization has different use cases. This section briefly describes what is different.

Binary:
 - as fast as possible
 - as small as possible. Just dump of data in memory
 - always serialize\deserialize entire world state. 
 - if some components can't be serialized (contain pointers to external objects such as files or engine), compilation error will be issued.
 As a solution, you can redefine serialization for such components to no-op and remove them before serialization
 - don't contain any information about structure of data. Loading from data saved in another version of application (with added\removed\changed component types) will fail in unpredictable way.
 - intended to just save\restore everything. Use cases - savegames, transmitting over network(WIP).

YAML:
 - not necessary fast or compact (still should be fast)
 - will link LibYAML to your binary (statically in case of Windows)
 - human-readable (and writable) format
 - only components inherited from ECS::YAMLComponent are saved
 - can add info to already non-empty world
 - intended to save\load only what is needed. Use cases - configs, loading of editable game data

## Benchmarks
See [Benchmarks](./Benchmarks.md)
## Plans
### Short-term
- [x] Reuse entity identifier, allows to replace `@sparse` hash with array
- [ ] generations of EntityID to catch usage of deleted entities
- [ ] better API for multiple components - iterating, array, deleting only one
- [ ] optimally delete multiple components (linked list)
- [x] bitmasks for entities. Could they improve performance? - no they don't
- [x] check that all singleframe components are deleted somewhere
- [x] benchmark comparison with flecs (https://github.com/jemc/crystal-flecs)
- [ ] groups from EnTT - could be useful?
- [x] Serialization
  - [ ] Flexible control of what components to skip
- [ ] Different contexts to simplify usage of different worlds
### Future
- [x] Callbacks on adding\deleting components
  - [x] Option to call deletion callbacks when clearing world
- [ ] Work with arena allocator to minimize usage of GC
## Contributors
- [Andrey Konovod](https://github.com/konovod) - creator and maintainer
