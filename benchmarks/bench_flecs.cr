require "benchmark"
require "flecs"

{% for i in 1..100 %}
ECS.component BenchComp{{i}} do
  property x : Int32
  property y : Int32

  def initialize(@x, @y)
  end
end
{% end %}

ECS.component Comp1 do
  property x : Int32
  property y : Int32

  def initialize(@x, @y)
  end
end
ECS.component Comp2 do
  property name : String

  def initialize(@name)
  end
end
ECS.component Comp3 do
  {% for i in (1..64) %}
  property heavy{{i}} : Int32 = 0
  {% end %}
end
# ECS.component Comp4 do
# end

ECS.component Comp5 do
  property vx : Int32
  property vy : Int32

  def initialize(@vx, @vy)
  end
end

ECS.system EmptySystem do
  phase "EcsOnUpdate"

  def self.run(iter)
  end
end

ECS.system EmptyFilterSystem do
  phase "EcsOnUpdate"

  term x : Comp5
  @@i = 0

  def self.run(iter)
    @@i = 0
    iter.each do |row|
      @@i += 1
    end
  end
end

# ECS.system FullFilterSystem do
#   phase "EcsOnUpdate"

#   # TODO or filter
#   term x : Comp1
#   term y : Comp2
#   term z : Comp3

#   # term t : Comp4
#   @@i = 0

#   def self.run(iter)
#     @@i = 0
#     iter.each do |row|
#       @@i += 1
#     end
#   end
# end

ECS.system SystemAddDeleteSingleComponent do
  phase "EcsOnUpdate"

  def self.run(iter)
    ent = iter.world.entity_init
    iter.world.set(ent, Comp1[-1, -1])
    iter.world.remove(ent, Comp1)
  end
end

ECS.system SystemAddDeleteFourComponents do
  phase "EcsOnUpdate"

  def self.run(iter)
    ent = iter.world.entity_init
    iter.world.set(ent, Comp1[-1, -1])
    iter.world.set(ent, Comp2["-1"])
    iter.world.set(ent, Comp3[])
    ECS::LibECS.entity_delete(iter.world, ent)
  end
end

ECS.system SystemGetComponent do
  phase "EcsOnUpdate"

  @@ent : UInt64 = 0
  @@i = 0

  def self.register2(world, positive)
    register(world)
    @@ent = world.entity_init
    if positive
      world.set(@@ent, Comp1[-1, -1])
    else
      world.set(@@ent, Comp5[-1, -1])
    end
  end

  def self.run(iter)
    @@i += 1 if iter.world.get(@@ent, Comp1)
  end
end

# class SystemGetSingletonComponent < ECS::System
#   @count = 0

#   def execute
#     conf = @world.new_entity.getConfig
#     @count = conf.values.size
#   end
# end

ECS.system SystemCountComp1 do
  phase "EcsOnUpdate"

  term x : Comp1
  @@i = 0

  def self.run(iter)
    @@i = 0
    iter.each do |row|
      @@i += 1
    end
  end
end

ECS.system SystemUpdateComp1 do
  phase "EcsOnUpdate"

  term comp1 : Comp1, write: true

  def self.run(iter)
    iter.each do |row|
      row.update_comp1 { |comp1|
        comp1.x = -comp1.x
        comp1.y = -comp1.y
        comp1
      }
      row.update_comp1 { |comp1|
        comp1.x = -comp1.x
        comp1.y = -comp1.y
        comp1
      }
    end
  end
end

ECS.system SystemReplaceComp1 do
  phase "EcsOnUpdate"

  term comp1 : Comp1, write: true

  def self.run(iter)
    iter.each do |row|
      comp1 = row.comp1
      iter.world.set(row.id, Comp5[comp1.x, comp1.y])
      iter.world.remove(row.id, Comp1)
    end
  end
end

ECS.system SystemReplaceComp5 do
  phase "EcsOnStore"

  term comp5 : Comp5, write: true

  def self.run(iter)
    iter.each do |row|
      comp5 = row.comp5
      iter.world.set(row.id, Comp1[comp5.vx, comp5.vy])
      iter.world.remove(row.id, Comp5)
    end
  end
end

# class SystemReplaceComp1 < ECS::System
#   def filter(world)
#     world.of(Comp1)
#   end

#   def process(entity)
#     comp = entity.getComp1
#     entity.replace(Comp1, Comp5.new(-comp.x, -comp.y))
#     comp5 = entity.getComp5
#     entity.replace(Comp5, Comp1.new(-comp.x, -comp.y))
#   end
# end

# class SystemComplexFilter < ECS::System
#   def filter(world)
#     world.any_of([Comp1, Comp2]).all_of([Comp3]).exclude(Comp4)
#   end

#   @count = 0

#   def process(entity)
#     @count += 1
#   end
# end

# class SystemComplexSelectFilter < ECS::System
#   def filter(world)
#     world.any_of([Comp1, Comp2]).all_of([Comp3]).exclude(Comp4).select { |ent| ent.id % 10 > 5 }
#   end

#   @count = 0

#   def process(entity)
#     @count += 1
#   end
# end

# class SystemGenerateEvent(Event) < ECS::System
#   @fixed_filter : ECS::Filter?

#   def initialize(@world, @fixed_filter = nil)
#     super(@world)
#   end

#   def filter(world)
#     @fixed_filter.not_nil!
#   end

#   def process(entity)
#     entity.add(Event.new)
#   end
# end

# class CountAllOf(Event) < ECS::System
#   def filter(world)
#     world.of(Event)
#   end

#   property value = 0

#   def process(entity)
#     @value += 1
#   end

#   def execute
#     @value = 0
#   end
# end

# class SystemPassEvents < ECS::Systems
#   def initialize(@world)
#     super
#     add SystemGenerateEvent(TestEvent1).new(@world, @world.of(Comp1))
#     add SystemGenerateEvent(TestEvent2).new(@world, @world.of(Comp2))
#     add SystemGenerateEvent(TestEvent3).new(@world, @world.all_of([TestEvent1, TestEvent2]))
#     add ECS::RemoveAllOf(TestEvent1).new(@world)
#     add ECS::RemoveAllOf(TestEvent2).new(@world)
#     add CountAllOf(TestEvent3).new(@world)
#     add ECS::RemoveAllOf(TestEvent3).new(@world)
#   end
# end

def init_benchmark_world(world, n)
  {% for i in 1..100 %}
    BenchComp{{i}}.register(world)
    ent = world.entity_init
    world.set(ent, BenchComp{{i}}[0, 0])
  {% end %}

  Comp1.register(world)
  Comp2.register(world)
  Comp3.register(world)
  # Comp4.register(world)
  Comp5.register(world)
  ent = world.entity_init
  world.set(ent, Comp5[0, 0])
  world.remove(ent, Comp5)
  n.times do |i|
    ent = world.entity_init
    world.set(ent, Comp1[i, i]) if i % 2 == 0
    world.set(ent, Comp2[i.to_s]) if i % 3 == 0
    # p 6
    world.set(ent, Comp3[]) if i % 5 == 0
    # p 7
    # world.set(ent, Comp4[]) if i % 7 == 0
  end
  return world
end

BENCH_N      = 1000000
BENCH_WARMUP =       1
BENCH_TIME   =       2

def benchmark_creation
  Benchmark.ips(warmup: BENCH_WARMUP, calculation: BENCH_TIME) do |bm|
    bm.report("create empty world") do
      world = ECS::World.init
      world.fini
    end
    bm.report("create benchmark world") do
      world = init_benchmark_world(ECS::World.init, BENCH_N)
      # world.fini
    end
    bm.report("create and clear benchmark world") do
      world = init_benchmark_world(ECS::World.init, BENCH_N)
      world.fini
    end
  end
end

def benchmark_list(list)
  puts "***********************************************"
  Benchmark.ips(warmup: BENCH_WARMUP, calculation: BENCH_TIME) do |bm|
    list.each do |cls|
      world = ECS::World.init
      cls.register(world)
      init_benchmark_world(world, BENCH_N)
      world.progress
      bm.report(cls.to_s) do
        world.progress
      end
      # world.fini
      # sys.teardown fails due to bm imlementation?
    end
  end
end

def benchmark_list2(list)
  puts "***********************************************"
  Benchmark.ips(warmup: BENCH_WARMUP, calculation: BENCH_TIME) do |bm|
    list.each do |cls|
      world = ECS::World.init
      init_benchmark_world(world, BENCH_N)
      cls.register2(world, false)
      world.progress
      bm.report(cls.to_s + "(0)") do
        world.progress
      end

      world = ECS::World.init
      init_benchmark_world(world, BENCH_N)
      cls.register2(world, true)
      world.progress
      bm.report(cls.to_s + "(1)") do
        world.progress
      end

      # world.fini
      # sys.teardown fails due to bm imlementation?
    end
  end
end

def benchmark_list3(list)
  puts "***********************************************"
  Benchmark.ips(warmup: BENCH_WARMUP, calculation: BENCH_TIME) do |bm|
    world = ECS::World.init
    list.each do |cls|
      cls.register(world)
    end
    init_benchmark_world(world, BENCH_N)
    world.progress
    bm.report("replace") do
      world.progress
    end
    # world.fini
    # sys.teardown fails due to bm imlementation?
  end
end

benchmark_list3 [
  SystemReplaceComp1,
  SystemReplaceComp5,
]

benchmark_creation

benchmark_list [
  EmptySystem,
  EmptyFilterSystem,
  SystemAddDeleteSingleComponent,
  SystemAddDeleteFourComponents,
  SystemCountComp1,
  SystemUpdateComp1,
  SystemReplaceComp1,
  # SystemGetSingletonComponent,
  #   SystemPassEvents,
  #   FullFilterSystem,
  #   FullFilterAnyOfSystem,
  #   SystemComplexFilter,
  #   SystemComplexSelectFilter,
]

benchmark_list2 [
  SystemGetComponent,
]
