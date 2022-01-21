<a href="https://github.com/konovod/myecs/actions/workflows/ci.yml">
      <img src="https://github.com/konovod/myecs/actions/workflows/ci.yml/badge.svg" alt="Build Status">
</a>

# MyECS

##### Table of Contents  
* [Main parts of ecs](#main-parts-of-ecs)
  * [Entity](#entity)
  * [Component](#component)
  * [System](#system)
* [Special components](#special-components)
  * [ECS::SingleFrame](#ecssingleframe)
  * [ECS::MultipleComponents](#ecsmultiplecomponents)
  * [ECS::SingletonComponent](#ecssingletoncomponent)
* [Other classes](#other-classes)
  * [ECS::World](#ecsworld)
  * [ECS::Filter](#ecsfilter)
  * [ECS::Systems](#ecssystems)
* [Engine integration](#engine-integration)
* [Other features](#other-features)
  * [Statistics](#statistics)
  * [component_exists?](#component_exists)
* [Benchmarks](#benchmarks)
* [Plans](#plans)
* [Contributors](#contributors)

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
User class can implement `init`, `execute`, `teardown`, `filter` and `process` (in any combination. Just skip methods you don't need).
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

  def execute
    # Will be called on each ECS::Systems.execute call
  end

  def teardown
    # Will be called once during ECS::Systems.teardown call
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
end
```

### Special components
#### ECS::SingleFrame
annotation `@[ECS::SingleFrame]` is for components that have to live 1 frame (usually - events). The main difference is that they are supposed to be deleted at once, so their storage can be simplified (no need to track free indexes). They should be deleted by adding `ECS::RemoveAllOf` system in a right place of systems list (or just using `.remove_singleframe(T)`).

```crystal
require "./src/myecs"

@[ECS::MultipleComponents]
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

#### ECS::MultipleComponents
Note above example also shows the use of `@[ECS::MultipleComponents]`. This is for components that can be added multiple times. They have some limitations though - filters can't iterate over several of components with this annotation (as this would usually mean cartesian product, unlikely needed in practice), there is no way to get multiple components outside of filter (it is planned though, but it won't be efficient nor cache-friendly), `delete` deletes all of components on target entity and there is no way to delete only one.
`ECS::MultipleComponents` can be combined with `ECS::SingleFrame` but that's not a requirement - there are perfectly correct use cases for `ECS::MultipleComponents` on persistent components - add several sprites to one renderable object or add several weapons to a tank. The only thing is that with current API you won't be able to remove single weapon ion that case - only remove all of them. So if you need better control over components just use good old "add an entity with single component and link it to parent entity" approach.

#### ECS::SingletonComponent
annotation `@[ECS::SingletonComponent]` is for data sharing. It creates component that is considered present on every entity (iteration on it isn't possible though). So you can do

```crystal
@[ECS::SingletonComponent]
record Config < ECS::Component, values : Hash(String, Int32)

class InitConfigSystem < ECS::System
  def init
    config = ...some config initializatio
    @world.new_entity.add(Config.new(config))
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

# you can create entity
world.new_entity

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
  - `select{|ent| some_check(ent) }`: user-provided filter procedure, that must return true for entity to be passed.

All of them can be called 0, 1, or many times using method chaining. 
So `any_of([Comp1, Comp2]).any_of([Comp3, Comp4])` means that either Comp1 or Comp2 should be present AND either Comp3 or Comp4 should be present.

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
    # world.of(IsATarget) will allocate a Filter, so you should create it at initialize and store it
    # so here is an easier way:
    world.query(IsATarget).each_entity do |target|
      range = distance(target.getPos, pos)
      if nearest_range > range
        nearest = target
        nearest_range = range
      end
    end
    # ...
  end
end
```

## Benchmarks
I'm comparing it with https://github.com/spoved/entitas.cr with some "realistic" scenario - creating world with 1_000_000 entities, adding and removing components in it, iterating over components, replacing components with another etc.
You can see I'm not actually beating it in all areas (I'm much slower in access but much faster in creation), but my ECS looks fast enough for me. What is I'm proud - 0.0B/op for all operations (after initial growth of pools)

my ECS:
```
***********************************************
              create empty world  84.22k ( 11.87µs) (±11.11%)  58.6kB/op          fastest
          create benchmark world  15.63  ( 63.96ms) (±11.85%)   246MB/op  5386.81× slower
create and clear benchmark world  15.15  ( 65.99ms) (±11.37%)   246MB/op  5557.26× slower
***********************************************
                   EmptySystem 185.63M (  5.39ns) (± 2.79%)  0.0B/op        fastest
             EmptyFilterSystem  33.41M ( 29.93ns) (± 1.27%)  0.0B/op   5.56× slower
SystemAddDeleteSingleComponent  23.68M ( 42.23ns) (±21.26%)  0.0B/op   7.84× slower
 SystemAddDeleteFourComponents  11.55M ( 86.55ns) (± 0.85%)  0.0B/op  16.07× slower
         SystemAskComponent(0) 114.19M (  8.76ns) (± 1.41%)  0.0B/op   1.63× slower
         SystemAskComponent(1) 114.25M (  8.75ns) (± 1.02%)  0.0B/op   1.62× slower
         SystemGetComponent(0) 127.06M (  7.87ns) (± 1.82%)  0.0B/op   1.46× slower
         SystemGetComponent(1) 112.55M (  8.89ns) (± 1.22%)  0.0B/op   1.65× slower
   SystemGetSingletonComponent 116.45M (  8.59ns) (± 1.13%)  0.0B/op   1.59× slower
 IterateOverCustomFilterSystem  88.22M ( 11.33ns) (± 0.91%)  0.0B/op   2.10× slower
***********************************************
         SystemCountComp1 257.13  (  3.89ms) (± 0.23%)  0.0B/op        fastest
        SystemUpdateComp1 110.32  (  9.06ms) (± 0.25%)  0.0B/op   2.33× slower
SystemUpdateComp1UsingPtr 221.70  (  4.51ms) (± 0.31%)  0.0B/op   1.16× slower
       SystemReplaceComp1  25.79  ( 38.77ms) (± 0.51%)  0.0B/op   9.97× slower
         SystemPassEvents  59.42  ( 16.83ms) (± 0.21%)  0.0B/op   4.33× slower
***********************************************
         FullFilterSystem  20.03  ( 49.93ms) (± 1.76%)  0.0B/op  12.76× slower
    FullFilterAnyOfSystem  86.23  ( 11.60ms) (± 0.46%)  0.0B/op   2.96× slower
      SystemComplexFilter 255.62  (  3.91ms) (± 1.14%)  0.0B/op        fastest
SystemComplexSelectFilter 235.79  (  4.24ms) (± 0.20%)  0.0B/op   1.08× slower
```
Entitas.cr (it is slightly outdated so you will have problems to make it work)
```
***********************************************
              create empty world   2.50M (399.61ns) (±16.26%)  1.66kB/op             fastest
          create benchmark world   1.55  (643.32ms) (±11.33%)  1.57GB/op  1609878.49× slower
create and clear benchmark world   1.04  (958.39ms) (± 0.87%)  1.67GB/op  2398325.42× slower
***********************************************
                   EmptySystem 320.60M (  3.12ns) (± 1.66%)    0.0B/op         fastest
             EmptyFilterSystem 244.01M (  4.10ns) (± 4.15%)    0.0B/op    1.31× slower
SystemAddDeleteSingleComponent 537.81k (  1.86µs) (±11.43%)  1.59kB/op  596.13× slower
 SystemAddDeleteFourComponents 487.55k (  2.05µs) (±15.30%)   1.6kB/op  657.57× slower
         SystemAskComponent(0) 216.22M (  4.63ns) (± 4.59%)    0.0B/op    1.48× slower
         SystemAskComponent(1) 216.62M (  4.62ns) (± 1.87%)    0.0B/op    1.48× slower
         SystemGetComponent(0) 217.34M (  4.60ns) (± 4.63%)    0.0B/op    1.48× slower
         SystemGetComponent(1) 216.66M (  4.62ns) (± 3.60%)    0.0B/op    1.48× slower
***********************************************
         SystemCountComp1   8.96k (111.57µs) (± 0.21%)    0.0B/op          fastest
        SystemUpdateComp1  22.47  ( 44.50ms) (± 0.43%)    0.0B/op   398.85× slower
SystemUpdateComp1UsingPtr   7.07  (141.54ms) (± 0.99%)    0.0B/op  1268.61× slower
       SystemReplaceComp1   4.46  (224.01ms) (± 1.19%)  3.81MB/op  2007.79× slower
***********************************************
     FullFilterSystem 215.91M (  4.63ns) (± 2.55%)  0.0B/op     1.00× slower
FullFilterAnyOfSystem 216.47M (  4.62ns) (± 2.01%)  0.0B/op          fastest
  SystemComplexFilter  39.19k ( 25.52µs) (± 0.31%)  0.0B/op  5524.39× slower
```

## Plans
### Short-term
- [x] Reuse entity identifier, allows to replace `@sparse` hash with array
- [ ] generations of EntityID to catch usage of deleted entities
- [ ] better API for multiple components - iterating, array, deleting onle one
- [ ] optimally delete multiple components (linked list)
- [X] check that all singleframe components are deleted somewhere
- [ ] benchmark comparison with flecs (https://github.com/jemc/crystal-flecs)
### Future
- [ ] Callbacks on adding\deleting components
- [ ] Work with arena allocator to minimize usage of GC
## Contributors
- [Andrey Konovod](https://github.com/konovod) - creator and maintainer
