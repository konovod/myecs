require "benchmark"
require "../src/myecs"

# UNCOMMENT TO MEASURE RELATIVE CHANGES

BASE_LINE =
  {
    "create empty world"                        => 11.23 * 1000,
    "create benchmark world"                    => 43.71*1000_000,
    "create and clear benchmark world"          => 43.10*1000_000,
    "serialize benchmark world"                 => 85.33*1000_000,
    "serialize and deserialize benchmark world" => 128.19*1000_000,
    "EmptySystem"                               => 5.05,
    "EmptyFilterSystem"                         => 26.08,
    "SystemAddDeleteSingleComponent"            => 31.40,
    "SystemAddDeleteFourComponents"             => 447.94,
    "SystemAskComponent(0)"                     => 7.28,
    "SystemAskComponent(1)"                     => 7.26,
    "SystemGetComponent(0)"                     => 8.5,
    "SystemGetComponent(1)"                     => 10.63,
    "SystemGetSingletonComponent"               => 7.28,
    "IterateOverCustomFilterSystem"             => 11.90,
    "SystemCountComp1"                          => 3.50 * 1000_000,
    "SystemUpdateComp1"                         => 9.15 * 1000_000,
    "SystemUpdateComp1UsingPtr"                 => 4.59 * 1000_000,
    "SystemReplaceComps"                        => 27.99*1000_000,
    "SystemPassEvents"                          => 35.66*1000_000,
    "FullFilterSystem"                          => 6.50*1000_000,
    "FullFilterAnyOfSystem"                     => 9.35*1000_000,
    "SystemComplexFilter"                       => 3.34*1000_000,
    "SystemComplexSelectFilter"                 => 3.39*1000_000,
  }

module Benchmark
  module IPS
    class Entry
      def human_compare
        sprintf "%5.2f", BASE_LINE[label] * mean / 1e9
      end
    end
  end
end

BENCH_COMPONENTS = 100

{% for i in 1..BENCH_COMPONENTS %} 
record BenchComp{{i}} < ECS::Component, vx : Int32, vy : Int32
{% end %}

record Comp1 < ECS::Component, x : Int32, y : Int32 do
  def change_x(value)
    @x = value
  end
end
record Comp2 < ECS::Component, name : String
record Comp3 < ECS::Component, heavy : StaticArray(Int32, 64)
record Comp4 < ECS::Component
record Comp5 < ECS::Component, vx : Int32, vy : Int32

@[ECS::SingleFrame]
record TestEvent1 < ECS::Component
@[ECS::SingleFrame]
record TestEvent2 < ECS::Component
@[ECS::SingleFrame]
record TestEvent3 < ECS::Component
@[ECS::Singleton]
record Config < ECS::Component, values : Hash(String, Int32)

class EmptySystem < ECS::System
  def execute
  end
end

class EmptyFilterSystem < ECS::System
  def filter(world)
    world.of(Comp5)
  end

  def process(entity)
  end
end

class IterateOverCustomFilterSystem < ECS::System
  @n = 0

  def execute
    @n = 0
    @world.query(Comp5).each do
      @n += 1
    end
  end
end

class FullFilterSystem < ECS::System
  def filter(world)
    world.exclude([Comp5])
  end

  def process(entity)
  end
end

class FullFilterAnyOfSystem < ECS::System
  def filter(world)
    world.any_of([Comp1, Comp2, Comp3, Comp4])
  end

  def process(entity)
  end
end

class SystemAddDeleteSingleComponent < ECS::System
  def execute
    ent = @world.new_entity.add(Comp1.new(-1, -1))
    ent.remove(Comp1)
  end
end

class SystemAddDeleteFourComponents < ECS::System
  def execute
    ent = @world.new_entity
    ent.add(Comp1.new(-1, -1))
    ent.add(Comp2.new("-1"))
    ent.add(Comp3.new(StaticArray(Int32, 64).new { |x| -x }))
    ent.add(Comp4.new)
    ent.destroy
  end
end

class SystemAskComponent(Positive) < ECS::System
  @ent : ECS::Entity

  def initialize(@world)
    @ent = uninitialized ECS::Entity
  end

  def init
    if Positive > 0
      @ent = @world.new_entity.add(Comp1.new(-1, -1))
    else
      @ent = @world.new_entity.add(Comp5.new(-1, -1))
    end
  end

  def execute
    @ent.has? Comp1
  end

  def teardown
    @ent.destroy
  end
end

class SystemGetComponent(Positive) < ECS::System
  @ent : ECS::Entity

  def initialize(@world)
    @ent = uninitialized ECS::Entity
  end

  def init
    if Positive > 0
      @ent = @world.new_entity.add(Comp1.new(-1, -1))
    else
      @ent = @world.new_entity.add(Comp5.new(-1, -1))
    end
  end

  def execute
    @ent.getComp1?
  end

  def teardown
    @ent.destroy
  end
end

class SystemGetSingletonComponent < ECS::System
  @count = 0

  def execute
    conf = @world.getConfig
    @count = conf.values.size
  end
end

class SystemCountComp1 < ECS::System
  def filter(world)
    world.of(Comp1)
  end

  @count = 0

  def process(entity)
    @count += 1
  end
end

class SystemUpdateComp1 < ECS::System
  def filter(world)
    world.of(Comp1)
  end

  def process(entity)
    comp = entity.getComp1
    entity.update(Comp1.new(-comp.x, -comp.y))
    comp = entity.getComp1
    entity.update(Comp1.new(-comp.x, -comp.y))
  end
end

class SystemUpdateComp1UsingPtr < ECS::System
  def filter(world)
    world.of(Comp1)
  end

  def process(entity)
    ptr_comp = entity.getComp1_ptr
    ptr_comp.value.change_x(ptr_comp.value.y)
  end
end

class SystemReplaceComp1 < ECS::System
  def filter(world)
    world.of(Comp1)
  end

  def process(entity)
    comp = entity.getComp1
    entity.replace(Comp1, Comp5.new(-comp.x, -comp.y))
  end
end

class SystemReplaceComp5 < ECS::System
  def filter(world)
    world.of(Comp5)
  end

  def process(entity)
    comp = entity.getComp5
    entity.replace(Comp5, Comp1.new(-comp.vx, -comp.vy))
  end
end

class SystemReplaceComps < ECS::Systems
  def initialize(@world)
    super
    add SystemReplaceComp1.new(@world)
    add SystemReplaceComp5.new(@world)
  end
end

class SystemComplexFilter < ECS::System
  def filter(world)
    world.any_of([Comp1, Comp2]).all_of([Comp3]).exclude(Comp4)
  end

  @count = 0

  def process(entity)
    @count += 1
  end
end

class SystemComplexSelectFilter < ECS::System
  def filter(world)
    world.any_of([Comp1, Comp2]).all_of([Comp3]).exclude(Comp4).filter { |ent| ent.id % 10 > 5 }
  end

  @count = 0

  def process(entity)
    @count += 1
  end
end

class SystemGenerateEvent(Event) < ECS::System
  @fixed_filter : ECS::Filter?

  def initialize(@world, @fixed_filter = nil)
    super(@world)
  end

  def filter(world)
    @fixed_filter.not_nil!
  end

  def process(entity)
    entity.add(Event.new)
  end
end

class CountAllOf(Event) < ECS::System
  def filter(world)
    world.of(Event)
  end

  property value = 0

  def process(entity)
    @value += 1
  end

  def execute
    @value = 0
  end
end

class SystemPassEvents < ECS::Systems
  def initialize(@world)
    super
    add SystemGenerateEvent(TestEvent1).new(@world, @world.of(Comp1))
    add SystemGenerateEvent(TestEvent2).new(@world, @world.of(Comp2))
    add SystemGenerateEvent(TestEvent3).new(@world, @world.all_of([TestEvent1, TestEvent2]))
    remove_singleframe(TestEvent1)
    remove_singleframe(TestEvent2)
    add CountAllOf(TestEvent3)
    remove_singleframe(TestEvent3)
  end
end

def init_benchmark_world(n)
  world = ECS::World.new
  config = Config.new(Hash(String, Int32).new)
  config.values["value"] = 1
  world.new_entity.add(config)
  world.new_entity.add(Comp5.new(0, 0)).remove(Comp5) # to init pool
  {% for i in 1..BENCH_COMPONENTS %} 
    world.new_entity.add(BenchComp{{i}}.new({{i}},{{i}}))
  {% end %}

  n.times do |i|
    ent = world.new_entity
    ent.add(Comp1.new(i, i)) if i % 2 == 0
    ent.add(Comp2.new(i.to_s)) if i % 3 == 0
    ent.add(Comp3.new(StaticArray(Int32, 64).new { |x| x + i })) if i % 5 == 0
    ent.add(Comp4.new) if i % 7 == 0
    ent.destroy_if_empty
  end
  return world
end

BENCH_N      = 1000000
BENCH_WARMUP =       2
BENCH_TIME   =       5

def benchmark_creation
  puts "***********************************************"
  Benchmark.ips(warmup: BENCH_WARMUP, calculation: BENCH_TIME) do |bm|
    bm.report("create empty world") do
      world = ECS::World.new
    end
    bm.report("create benchmark world") do
      world = init_benchmark_world(BENCH_N)
    end
    bm.report("create and clear benchmark world") do
      world = init_benchmark_world(BENCH_N)
      world.delete_all
    end
    # bm.report("serialize empty world") do
    #   world = ECS::World.new
    #   aio = IO::Memory.new
    #   world.encode aio
    #   aio.rewind
    #   world2 = ECS::World.new
    #   world2.decode aio
    # end
    first = true
    bm.report("serialize benchmark world") do
      world = init_benchmark_world(BENCH_N)
      aio = IO::Memory.new
      world.encode aio
      if first
        puts aio.pos
        first = false
      end
    end
    bm.report("serialize and deserialize benchmark world") do
      world = init_benchmark_world(BENCH_N)
      aio = IO::Memory.new
      world.encode aio
      n = aio.pos
      world2 = ECS::World.new
      aio.rewind
      world2.decode aio
      raise "#{aio.pos} vs #{n}" unless aio.pos == n
    end
  end
end

macro benchmark_list(*list)
  puts "***********************************************"
  world = init_benchmark_world(BENCH_N)
  list = [] of ECS::Systems
  {% for cls in list %}
    %sys = ECS::Systems.new(world)
    %sys.add({{cls}})
    list << %sys
  {% end %}



  Benchmark.ips(warmup: BENCH_WARMUP, calculation: BENCH_TIME) do |bm|
    list.each do |sys|
      sys.init
      sys.execute
      bm.report(sys.children[0].class.name) do
        sys.execute
      end
      # sys.teardown fails due to bm imlementation?
    end
  end
end

puts init_benchmark_world(BENCH_N).stats

benchmark_creation

benchmark_list(EmptySystem,
  EmptyFilterSystem,
  SystemAddDeleteSingleComponent,
  SystemAddDeleteFourComponents,
  SystemAskComponent(0),
  SystemAskComponent(1),
  SystemGetComponent(0),
  SystemGetComponent(1),
  SystemGetSingletonComponent,
  IterateOverCustomFilterSystem,
)

benchmark_list(SystemCountComp1,
  SystemUpdateComp1,
  SystemUpdateComp1UsingPtr,
  SystemReplaceComps,
  SystemPassEvents,
)

benchmark_list(FullFilterSystem,
  FullFilterAnyOfSystem,
  SystemComplexFilter,
  SystemComplexSelectFilter,
)

ECS.debug_stats
