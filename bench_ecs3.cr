require "benchmark"
require "./src/myecs"

record PositionComponent < ECS::Component, x : Float32, y : Float32 do
  def update_x(value)
    @x = value
  end

  def update_y(value)
    @y = value
  end
end

record DirectionComponent < ECS::Component, x : Float32, y : Float32

record ComflabulationComponent < ECS::Component, thingy : Float32, dingy : Int32, mingy : Bool, stringy : String

DT = 1.0 / 60

class MovementSystem < ECS::System
  def filter(world)
    world.all_of([PositionComponent, DirectionComponent])
  end

  def process(entity)
    pos = entity.getPositionComponent_ptr
    dir = entity.getDirectionComponent
    pos.value.update_x(pos.value.x + dir.x*DT)
    pos.value.update_y(pos.value.y + dir.y*DT)
  end
end

class ComflabSystem < ECS::System
  def filter(world)
    world.of(ComflabulationComponent)
  end

  def process(entity)
    comp = entity.getComflabulationComponent
    entity.update(ComflabulationComponent.new(comp.thingy*1.000001f32, comp.dingy + 1, !comp.mingy, comp.stringy))
  end
end

N_10M = 10_000_000

def report(x, &)
  puts x, Benchmark.measure { yield }
end

def benchmark1
  world = ECS::World.new
  report("Creating 10M entities") do
    N_10M.times do
      world.new_entity
    end
  end
  world.delete_all

  list = [] of ECS::Entity
  N_10M.times do
    list << world.new_entity
  end
  report("Destroying 10M entities") do
    list.each &.destroy
  end

  N_10M.times do
    world.new_entity
  end
  report("Destroying 10M entities at once") do
    world.delete_all
  end

  N_10M.times do
    ent = world.new_entity
    ent.add(PositionComponent.new(0, 0))
  end
  report("Iterating over 10M entities, unpacking one component") do
    world.query(PositionComponent).each_entity do |ent|
      v = ent.getPositionComponent
      puts v.y if v.x < -0.5
    end
  end
  world.delete_all

  N_10M.times do
    ent = world.new_entity
    ent.add(PositionComponent.new(0, 0))
    ent.add(DirectionComponent.new(0, 0))
  end
  report("Iterating over 10M entities, unpacking two component") do
    world.query(PositionComponent).each_entity do |ent|
      v = ent.getPositionComponent
      w = ent.getDirectionComponent
      puts v.y if w.x < -0.5
    end
  end
  world.delete_all

  sys = ECS::Systems.new(world)
  sys.add MovementSystem
  sys.add ComflabSystem
  sys.init
  [1, 2, 5, 10, 20].each do |n|
    (n*1_000_000).times do |i|
      ent = world.new_entity
      ent.add(PositionComponent.new(0, 0))
      ent.add(DirectionComponent.new(0, 0))
      if i % 2 == 0
        ent.add(ComflabulationComponent.new(0, 0, false, ""))
      end
    end
    report("Update #{n}M entities with 2 Systems") do
      sys.execute
    end
    world.delete_all
  end
end

ECS.debug_stats
benchmark1
