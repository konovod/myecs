require "benchmark"
require "../src/myecs"

record Comp1 < ECS::Component, x : Int32 do
  def change_x(value)
    @x = value
  end
end

record Comp2 < ECS::Component, x : Int32
record Comp3 < ECS::Component, x : Int32

class SystemUpdateComp1 < ECS::System
  def filter(world)
    world.of(Comp1)
  end

  def process(entity)
    comp = entity.getComp1
    entity.update(Comp1.new(comp.x + 1))
  end
end

class SystemUpdateComp1UsingPtr < ECS::System
  def filter(world)
    world.of(Comp1)
  end

  def process(entity)
    ptr_comp = entity.getComp1_ptr
    ptr_comp.value.change_x(ptr_comp.value.x + 1)
  end
end

class SystemUpdateComp3 < ECS::System
  def filter(world)
    world.all_of([Comp1, Comp2, Comp3])
  end

  def process(entity)
    comp1 = entity.getComp1
    comp2 = entity.getComp2
    comp3 = entity.getComp3
    entity.update(Comp1.new(comp1.x + comp2.x + comp3.x))
  end
end

class SystemUpdateComp3UsingPtr < ECS::System
  def filter(world)
    world.all_of([Comp1, Comp2, Comp3])
  end

  def process(entity)
    comp1 = entity.getComp1_ptr
    comp2 = entity.getComp2_ptr
    comp3 = entity.getComp3_ptr
    comp1.value.change_x(comp1.value.x + comp2.value.x + comp3.value.x)
  end
end

def direct_increment(world, three)
  if three
    pool1 = world.pool_for(Comp1.new(0)).@raw
    pool2 = world.pool_for(Comp2.new(0)).@raw
    pool3 = world.pool_for(Comp3.new(0)).@raw
    # pp! pool1.size, pool2.size, pool3.size
    BENCH_N.times do |i|
      pool1[i].change_x(pool1[i].x + pool2[i].x + pool3[i].x)
    end
  else
    world.pool_for(Comp1.new(0)).@raw.map! { |x| Comp1.new(x.x + 1) }
  end
end

def init_benchmark_world(n, three, padding)
  world = ECS::World.new
  n *= 10 if padding
  if three
    n.times do |i|
      ent = world.new_entity
      if (!padding) || i % 10 == 0
        ent.add(Comp1.new(1))
        ent.add(Comp2.new(1))
        ent.add(Comp3.new(1))
      else
        case i % 3
        when 0
          ent.add(Comp1.new(1))
        when 1
          ent.add(Comp2.new(1))
        when 2
          ent.add(Comp3.new(1))
        end
      end
    end
  else
    n.times do |i|
      ent = world.new_entity
      if (!padding) || i % 10 == 0
        ent.add(Comp1.new(1))
      else
        ent.add(Comp2.new(1))
      end
    end
  end
  return world
end

BENCH_N      = 100000
BENCH_WARMUP =      1
BENCH_TIME   =      2

macro benchmark_list(three, *list)
  puts "***********************************************"
  puts "Three: {{three}}"
  world = init_benchmark_world(BENCH_N, {{three}}, false)
  worldp = init_benchmark_world(BENCH_N, {{three}}, true)
  puts world.stats
  puts worldp.stats
  list = [] of {ECS::Systems, String}
  {% for cls in list %}
    %sys = ECS::Systems.new(world)
    %sys.add({{cls}})
    list << { %sys, ""}
    %sys2 = ECS::Systems.new(worldp)
    %sys2.add({{cls}})
    list << { %sys2, "padded"}
  {% end %}

  Benchmark.ips(warmup: BENCH_WARMUP, calculation: BENCH_TIME) do |bm|

      bm.report("direct") do
        direct_increment(world, {{three}})
      end

    list.each do |(sys, prefix)|
      sys.init
      sys.execute
      bm.report("#{prefix} #{sys.children[0].class.name}") do
        sys.execute
      end
      # sys.teardown fails due to bm imlementation?
    end
  end
end

benchmark_list(false,
  SystemUpdateComp1,
  SystemUpdateComp1UsingPtr
)
benchmark_list(true,
  SystemUpdateComp3,
  SystemUpdateComp3UsingPtr
)

ECS.debug_stats
