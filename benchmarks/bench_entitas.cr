require "benchmark"
require "entitas"

annotation SingleFrame; end

{% for i in 1..100 %}
@[Context(Game)]
class BenchComp{{i}} < Entitas::Component
  prop :x, Int32
  prop :y, Int32
end
{% end %}

@[Context(Game)]
class Comp1 < Entitas::Component
  prop :x, Int32
  prop :y, Int32
end

@[Context(Game)]
class Comp2 < Entitas::Component
  prop :name, String
end

@[Context(Game)]
class Comp3 < Entitas::Component
  prop :heavy, StaticArray(Int32, 64)
end

@[Context(Game)]
class Comp4 < Entitas::Component
end

@[Context(Game)]
class Comp5 < Entitas::Component
  prop :vx, Int32
  prop :vy, Int32
end

@[Context(Game)]
# @[SingleFrame]
class TestEvent1 < Entitas::Component
end

@[Context(Game)]
# @[SingleFrame]
class TestEvent2 < Entitas::Component
end

@[Context(Game)]
# @[SingleFrame]
class TestEvent3 < Entitas::Component
end

class EmptySystem
  include Entitas::Systems::ExecuteSystem

  def initialize(@context : GameContext)
  end

  def execute
  end
end

class EmptyFilterSystem
  include Entitas::Systems::ExecuteSystem

  getter context : GameContext
  getter filter : Entitas::Group(GameEntity)

  def initialize(@context : GameContext)
    @filter = context.get_group(Entitas::Matcher.all_of(Comp5))
  end

  def execute
    @filter.get_entities.each do |ent|
    end
  end
end

class FullFilterSystem
  include Entitas::Systems::ExecuteSystem

  getter context : GameContext
  getter filter : Entitas::Group(GameEntity)

  def initialize(@context : GameContext)
    @filter = context.get_group(Entitas::Matcher.none_of(Comp5))
  end

  def execute
    @filter.get_entities.each do |ent|
    end
  end
end

class FullFilterAnyOfSystem
  include Entitas::Systems::ExecuteSystem

  getter context : GameContext
  getter filter : Entitas::Group(GameEntity)

  def initialize(@context : GameContext)
    @filter = context.get_group(Entitas::Matcher.any_of(Comp1, Comp2, Comp3, Comp4, Comp5))
  end

  def execute
    @filter.get_entities.each do |ent|
    end
  end
end

class SystemAddDeleteSingleComponent
  include Entitas::Systems::ExecuteSystem

  def initialize(@context : GameContext)
  end

  def execute
    ent = @context.create_entity.add_comp1(x: -1, y: -1)
    ent.del_comp1
  end
end

class SystemAddDeleteFourComponents
  include Entitas::Systems::ExecuteSystem

  def initialize(@context : GameContext)
  end

  def execute
    ent = @context.create_entity.add_comp1(x: -1, y: -1).add_comp2(name: "-1").add_comp3(heavy: StaticArray(Int32, 64).new { |x| -x }).add_comp4
    ent.del_comp1
    ent.del_comp2
    ent.del_comp3
    ent.del_comp4
  end
end

class SystemAskComponent(Positive)
  include Entitas::Systems::ExecuteSystem

  @ent : Entitas::Entity

  def initialize(@context : GameContext)
    if Positive > 0
      @ent = @context.create_entity.add_comp1(x: -1, y: -1)
    else
      @ent = @context.create_entity.add_comp5(vx: -1, vy: -1)
    end
  end

  def execute
    @ent.has_comp1?
  end
end

class SystemGetComponent(Positive)
  include Entitas::Systems::ExecuteSystem

  @ent : Entitas::Entity

  def initialize(@context : GameContext)
    if Positive > 0
      @ent = @context.create_entity.add_comp1(x: -1, y: -1)
    else
      @ent = @context.create_entity.add_comp5(vx: -1, vy: -1)
    end
  end

  def execute
    @ent.comp1?
  end
end

# class SystemGetSingletonComponent < ECS::System
#   @count = 0

#   def execute
#     conf = @world.new_entity.getConfig
#     @count = conf.values.size
#   end
# end

class SystemCountComp1
  include Entitas::Systems::ExecuteSystem

  getter context : GameContext
  getter filter : Entitas::Group(GameEntity)

  @count = 0

  def initialize(@context : GameContext)
    @filter = context.get_group(Entitas::Matcher.all_of(Comp1))
  end

  def execute
    v = 0
    @filter.get_entities.each do |ent|
      v += 1
    end
    @count = @count ^ v
  end
end

class SystemUpdateComp1
  include Entitas::Systems::ExecuteSystem

  getter context : GameContext
  getter filter : Entitas::Group(GameEntity)

  def initialize(@context : GameContext)
    @filter = context.get_group(Entitas::Matcher.all_of(Comp1))
  end

  def execute
    @filter.get_entities.each do |ent|
      comp1 = ent.comp1
      comp1.x = -comp1.x
      comp1.y = -comp1.y
      comp1 = ent.comp1
      comp1.x = -comp1.x
      comp1.y = -comp1.y
    end
  end
end

class SystemUpdateComp1UsingPtr
  include Entitas::Systems::ExecuteSystem

  getter context : GameContext
  getter filter : Entitas::Group(GameEntity)

  def initialize(@context : GameContext)
    @filter = context.get_group(Entitas::Matcher.all_of(Comp1))
  end

  def execute
    @filter.get_entities.each do |ent|
      comp1 = ent.comp1
      ent.replace_comp1(x: -comp1.x, y: -comp1.y)
      comp1 = ent.comp1
      ent.replace_comp1(x: -comp1.x, y: -comp1.y)
    end
  end
end

class SystemReplaceComp1
  include Entitas::Systems::ExecuteSystem

  getter context : GameContext
  getter filter : Entitas::Group(GameEntity)

  def initialize(@context : GameContext)
    @filter = context.get_group(Entitas::Matcher.all_of(Comp1))
  end

  def execute
    @filter.get_entities.each do |ent|
      comp1 = ent.comp1
      ent.del_comp1
      ent.add_comp5(vx: comp1.x, vy: comp1.y)
      comp5 = ent.comp5
      ent.del_comp5
      ent.add_comp1(x: comp5.vx, y: comp5.vy)
    end
  end
end

class SystemComplexFilter
  include Entitas::Systems::ExecuteSystem

  getter context : GameContext
  getter filter : Entitas::Group(GameEntity)

  @count = 0

  def initialize(@context : GameContext)
    @filter = context.get_group(Entitas::Matcher.any_of(Comp1, Comp2).all_of(Comp3).none_of(Comp4))
  end

  def execute
    v = 0
    @filter.get_entities.each do |ent|
      v += 1
    end
    @count = @count ^ v
  end
end

# class SystemComplexSelectFilter
#   include Entitas::Systems::ExecuteSystem

#   getter context : GameContext
#   getter filter : Entitas::Group(GameEntity)

#   @count = 0

#   def initialize(@context : GameContext)
#     @filter = context.get_group(Entitas::Matcher.any_of(Comp1, Comp2).all_of(Comp3).none_of(Comp4))
#   end

#   def execute
#     @filter.get_entities.each do |ent|
#       next unless ent.id % 10 > 5
#       @count += 1
#     end
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

# class SystemPassEvents < ECS::Systems
#   def initialize(@world)
#     super
#     add SystemGenerateEvent(TestEvent1).new(@world, @world.of(Comp1))
#     add SystemGenerateEvent(TestEvent2).new(@world, @world.of(Comp2))
#     add SystemGenerateEvent(TestEvent3).new(@world, @world.all_of([TestEvent1, TestEvent2]))
#     # add SystemGenerateEvent(TestEvent1).new(@world, @world.of(TestEvent3))
#   end
# end

def init_benchmark_world(n)
  ctx = GameContext.new
  # config = Config.new(Hash(String, Int32).new)
  # config.values["value"] = 1
  # world.new_entity.add(config)
  ent = ctx.create_entity.add_comp5(vx: 0, vy: 0)
  ent.del_comp5

  {% for i in 1..100 %}
	ent = ctx.create_entity.add_bench_comp{{i}}(x: 0, y: 0)
{% end %}

  n.times do |i|
    ent = ctx.create_entity
    ent.add_comp1(x: i, y: i) if i % 2 == 0
    ent.add_comp2(name: i.to_s) if i % 3 == 0
    ent.add_comp3(heavy: StaticArray(Int32, 64).new { |x| x + i }) if i % 5 == 0
    ent.add_comp4 if i % 7 == 0
  end
  return ctx
end

BENCH_N      = 500000
BENCH_WARMUP =      1
BENCH_TIME   =      2

def benchmark_creation
  Benchmark.ips(warmup: BENCH_WARMUP, calculation: BENCH_TIME) do |bm|
    bm.report("create empty world") do
      ctx = GameContext.new
    end
    bm.report("create benchmark world") do
      init_benchmark_world(BENCH_N)
    end
    bm.report("create and clear benchmark world") do
      ctx = init_benchmark_world(BENCH_N)
      ctx.destroy_all_entities
    end
  end
end

def benchmark_list(list)
  puts "***********************************************"
  world = init_benchmark_world(BENCH_N)
  Benchmark.ips(warmup: BENCH_WARMUP, calculation: BENCH_TIME) do |bm|
    list.each do |cls|
      GC.collect
      ctx = init_benchmark_world(BENCH_N)
      sys = Entitas::Feature.new("all")
      sys.add(cls.new(ctx))
      sys.init
      sys.execute
      bm.report(cls.to_s) do
        sys.execute
      end
      sys.tear_down
    end
  end
end

benchmark_creation

benchmark_list [
  EmptySystem,
  EmptyFilterSystem,
  SystemAddDeleteSingleComponent,
  SystemAddDeleteFourComponents,
  SystemAskComponent(0),
  SystemAskComponent(1),
  SystemGetComponent(0),
  SystemGetComponent(1),
  # SystemGetSingletonComponent,
]

benchmark_list [
  SystemCountComp1,
  SystemUpdateComp1,
  SystemUpdateComp1UsingPtr,
  SystemReplaceComp1,
  # SystemPassEvents,
]

benchmark_list [
  FullFilterSystem,
  FullFilterAnyOfSystem,
  SystemComplexFilter,
  # SystemComplexSelectFilter,
]
