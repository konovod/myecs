require "./spec_helper"

record Pos < ECS::Component, x : Int32, y : Int32 do
  def change_x(value)
    @x = value
  end
end
record Speed < ECS::Component, vx : Int32, vy : Int32
record Name < ECS::Component, name : String

@[ECS::SingleFrame]
record TestEvent1 < ECS::Component
@[ECS::SingleFrame(check: true)]
record TestEvent2 < ECS::Component
@[ECS::SingleFrame]
record TestEvent3 < ECS::Component

@[ECS::SingleFrame(check: false)]
record TestEventNotChecked < ECS::Component

def count_entities(where)
  n = 0
  where.each_entity do |e|
    n += 1
  end
  n
end

describe ECS do
  it "adds component" do
    world = ECS::World.new
    ent = world.new_entity
    ent.add(Pos.new(1, 1))
    ent.getPos.should eq Pos.new(1, 1)
    typeof(ent.getPos).should eq(Pos)
    typeof(ent.getPos?).should eq(Pos | Nil)
    ent.has?(Pos).should be_true
    ent.has?(Speed).should be_false
    ent.getSpeed?.should be_nil
    ent.add(Speed.new(2, 2))
    ent.has?(Speed).should be_true
    ent.getPos.should eq Pos.new(1, 1)
    ent.getSpeed.should eq Speed.new(2, 2)
    ent.getSpeed?.should eq Speed.new(2, 2)
    # ent.components.size.should eq 2
  end

  it "world can iterate without entities" do
    world = ECS::World.new
    count_entities(world).should eq 0
  end

  it "entity can add and delete component repeatedly" do
    world = ECS::World.new
    ent = world.new_entity
    ent.add(Speed.new(1, 1))
    pos = Pos.new(5, 6)
    10.times do
      ent.add(pos)
      ent.remove(Pos)
    end
  end

  it "remove components" do
    world = ECS::World.new
    ent = world.new_entity
    ent.add(Pos.new(1, 1))
    ent.add(Speed.new(2, 2))
    ent.remove(Pos)
    ent.has?(Pos).should be_false
    ent.has?(Speed).should be_true
    ent.add(Pos.new(1, 1))
    ent.has?(Pos).should be_true
    ent.remove(Speed)
    ent.has?(Speed).should be_false
  end

  it "replace components" do
    world = ECS::World.new
    ent = world.new_entity
    ent.add(Pos.new(1, 1))
    ent.replace(Pos, Speed.new(1, 1))
    ent.has?(Pos).should be_false
    ent.has?(Speed).should be_true
    ent.getSpeed.should eq Speed.new(1, 1)
  end

  it "update components with same type" do
    world = ECS::World.new
    ent = world.new_entity
    ent.add(Pos.new(1, 1))
    ent.update(Pos.new(2, 2))
    ent.has?(Pos).should be_true
    ent.getPos.should eq Pos.new(2, 2)
  end

  it "can't add components with same type twice" do
    world = ECS::World.new
    ent = world.new_entity
    ent.add(Pos.new(1, 1))
    expect_raises(Exception) { ent.add(Pos.new(2, 2)) }
  end

  it "can set components with same type" do
    world = ECS::World.new
    ent = world.new_entity
    ent.set(Pos.new(1, 1))
    ent.set(Pos.new(2, 2))
    ent.has?(Pos).should be_true
    ent.getPos.should eq Pos.new(2, 2)
    world.of(Pos).size.should eq 1
  end

  it "receive component pointer" do
    world = ECS::World.new
    ent = world.new_entity
    ent.add(Pos.new(1, 1))
    ptr = ent.getPos_ptr
    ptr.value.change_x(2)
    ent.getPos.should eq Pos.new(2, 1)
  end

  it "remove entities" do
    world = ECS::World.new
    ent = world.new_entity
    ent2 = world.new_entity
    ent.add(Pos.new(1, 1))
    ent.add(Speed.new(1, 1))
    ent2.add(Speed.new(1, 2))
    count_entities(world).should eq 2
    ent.destroy
    count_entities(world).should eq 1
    ent2.destroy
    count_entities(world).should eq 0
  end

  it "remove entities by components" do
    world = ECS::World.new
    ent = world.new_entity
    ent2 = world.new_entity
    ent.add(Pos.new(1, 1))
    ent.add(Speed.new(1, 1))
    ent2.add(Speed.new(1, 2))
    ent.remove(Speed)
    count_entities(world).should eq 2
    ent.remove(Pos)
    count_entities(world).should eq 1
  end

  it "can iterate using filters" do
    world = ECS::World.new
    ent = world.new_entity
    ent2 = world.new_entity
    ent.add(Pos.new(1, 1))
    filter = world.of(Speed)
    filter.size.should eq 0
    ent2.add(Speed.new(1, 1))
    filter.size.should eq 1
    ent2.add(Pos.new(1, 1))
    ent2.remove(Speed)
    filter.size.should eq 0
  end

  it "can iterate using filters with all_of" do
    world = ECS::World.new
    ent = world.new_entity
    ent2 = world.new_entity
    ent.add(Pos.new(1, 1))
    ent2.add(Pos.new(1, 1))
    world.all_of([Pos, Speed]).size.should eq 0
    ent2.add(Speed.new(1, 1))
    world.all_of([Pos, Speed]).size.should eq 1
    world.all_of([Pos]).size.should eq 2
    world.all_of([Pos, Name]).size.should eq 0
    world.all_of([Name]).size.should eq 0
  end
  it "can iterate using filters with any_of" do
    world = ECS::World.new
    world.new_entity.add(Pos.new(1, 1))
    world.any_of([Name, Speed]).size.should eq 0
    world.new_entity.add(Pos.new(1, 1)).add(Speed.new(1, 1))
    world.new_entity.add(Speed.new(1, 1))
    world.any_of([Pos, Speed]).size.should eq 3
    world.any_of([Name, Pos]).size.should eq 2
  end

  it "any_of works with single item" do
    world = ECS::World.new
    world.new_entity.add(Pos.new(1, 1))
    world.any_of([Pos]).size.should eq 1
    world.new_entity.add(Pos.new(1, 1)).add(Speed.new(1, 1))
    world.new_entity.add(Speed.new(1, 1))
    world.any_of([Pos]).size.should eq 2
    world.any_of([Name]).size.should eq 0
  end

  it "can filter using exclude" do
    world = ECS::World.new
    world.new_entity.add(Pos.new(1, 1))
    world.new_entity.add(Pos.new(1, 1)).add(Speed.new(1, 1))
    world.new_entity.add(Speed.new(1, 1))
    world.of(Pos).exclude(Speed).size.should eq 1
    world.exclude([Speed]).size.should eq 1
    world.exclude(Name).size.should eq 3
    world.exclude([Name, Pos]).size.should eq 1
  end
  it "can filter using select" do
    world = ECS::World.new
    world.new_entity.add(Pos.new(1, 1))
    world.new_entity.add(Pos.new(1, -1)).add(Speed.new(1, 1))
    world.new_entity.add(Speed.new(1, 2))
    world.of(Pos).select { |ent| ent.getPos.y > 0 }.size.should eq 1
    expect_raises(Exception) { world.new_filter.select { |ent| ent.getPos.y > 0 }.size }
  end

  it "can found single entity" do
    world = ECS::World.new
    world.of(Pos).first?.should eq nil
    ent = world.new_entity.add(Pos.new(1, 1))
    world.of(Pos).first?.should eq ent
    ent.destroy
    world.of(Pos).first?.should eq nil
  end

  it "can add component of runtime type" do
    world = ECS::World.new
    ent = world.new_entity
    event = rand < 0.5 ? Pos.new(1, 1) : Speed.new(2, 2)
    ent.add(event)
    world.any_of([Pos, Speed]).first?.should eq ent
  end
end

class TestSystem < ECS::System
  getter init_called = 0
  getter execute_called = 0
  getter teardown_called = 0

  def init
    @init_called += 1
  end

  def execute
    @execute_called += 1
  end

  def teardown
    @teardown_called += 1
  end
end

class TestReactiveSystem < ECS::System
  getter execute_called = 0

  def execute
    @execute_called += 1
  end

  def filter(world)
    world.all_of([Pos, Speed])
  end

  def process(entity)
    new_pos = Pos.new(entity.getPos.x + entity.getSpeed.vx, entity.getPos.y + entity.getSpeed.vy)
    entity.update(new_pos)
  end
end

describe ECS::Systems do
  it "can add, init, execute and teardown systems" do
    world = ECS::World.new
    world.new_entity.add(Pos.new(1, 1))
    sys1 = TestSystem.new(world)
    sys2 = TestSystem.new(world)
    systems = ECS::Systems.new(world).add(sys1).add(sys2)
    sys1.init_called.should eq 0
    systems.init
    sys1.init_called.should eq 1
    sys2.init_called.should eq 1

    sys1.execute_called.should eq 0
    systems.execute
    sys1.execute_called.should eq 1

    sys2.teardown_called.should eq 0
    systems.teardown
    sys1.teardown_called.should eq 1
  end

  it "raises if wasn't initialized" do
    world = ECS::World.new
    systems = ECS::Systems.new(world)
    expect_raises(Exception, "initialized") { systems.execute }
  end

  it "can process entities" do
    world = ECS::World.new
    ent = world.new_entity.add(Pos.new(1, 1))
    ent.add(Speed.new(10, 10))
    sys1 = TestReactiveSystem.new(world)
    systems = ECS::Systems.new(world).add(sys1)
    systems.init
    sys1.execute_called.should eq 0
    systems.execute
    sys1.execute_called.should eq 1
    ent.getPos.x.should eq 10 + 1
  end

  it "honour active property" do
    world = ECS::World.new
    ent = world.new_entity.add(Pos.new(1, 1))
    ent.add(Speed.new(10, 10))
    systems = ECS::Systems.new(world)
    sys1 = TestReactiveSystem.new(world)
    sys2 = TestSystem.new(world)
    systems.add(sys1).add(sys2)
    systems.init
    sys1.execute_called.should eq 0
    sys2.execute_called.should eq 0
    systems.execute
    sys1.execute_called.should eq 1
    sys2.execute_called.should eq 1
    ent.getPos.x.should eq 10 + 1

    sys1.active = false
    systems.execute
    sys1.execute_called.should eq 1
    sys2.execute_called.should eq 2
    ent.getPos.x.should eq 10 + 1

    sys1.active = true
    sys2.active = false
    systems.execute
    sys1.execute_called.should eq 2
    sys2.execute_called.should eq 2
    ent.getPos.x.should eq 10 + 10 + 1
  end
end

class ReplaceEventsSystem(EventFrom, EventTo) < ECS::System
  def filter(world)
    world.of(EventFrom)
  end

  def process(entity)
    entity.add(EventTo.new)
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
end

class GenerateEventsSystem(Event) < ECS::System
  def execute
    @world.new_entity.add(Event.new)
  end
end

class GenerateEventsInInitSystem(Event) < ECS::System
  def init
    @world.new_entity.add(Event.new)
  end
end

describe ECS::SingleFrame do
  it "is deleted correctly" do
    world = ECS::World.new
    counter_before = CountAllOf(TestEvent3).new(world)
    counter_after = CountAllOf(TestEvent3).new(world)
    systems = ECS::Systems.new(world)
      .add(ReplaceEventsSystem(TestEvent2, TestEvent3).new(world))
      .remove_singleframe(TestEvent2)
      .add(counter_before)
      .remove_singleframe(TestEvent3)
      .add(counter_before)
      .add(ReplaceEventsSystem(TestEvent1, TestEvent2).new(world))
      .remove_singleframe(TestEvent1)
      .add(GenerateEventsSystem(TestEvent1).new(world))
    systems.init
    systems.execute
    counter_before.value.should eq 0
    counter_after.value.should eq 0
    systems.execute
    counter_before.value.should eq 0
    counter_after.value.should eq 0
    systems.execute
    counter_before.value.should eq 1
    counter_after.value.should eq 0
  end

  it "is checked that they are deleted somewhere" do
    world = ECS::World.new
    systems = ECS::Systems.new(world)
    systems.init
    expect_raises(Exception) { world.new_entity.add(TestEvent1.new) }
    systems.remove_singleframe(TestEvent1)
    world.new_entity.add(TestEvent1.new)
    world.of(TestEvent1).size.should eq 1
    systems.execute
    world.of(TestEvent1).size.should eq 0
  end
  it "isn't checked that they are deleted somewhere if annotation specify it" do
    world = ECS::World.new
    systems = ECS::Systems.new(world)
    systems.init
    world.of(TestEventNotChecked).size.should eq 0
    world.new_entity.add(TestEventNotChecked.new)
    world.of(TestEventNotChecked).size.should eq 1
    systems.execute
    world.of(TestEventNotChecked).size.should eq 1
    world.new_entity.add(TestEventNotChecked.new)
    world.of(TestEventNotChecked).size.should eq 2
  end
end

@[ECS::Singleton]
record Config < ECS::Component, value : Int32

describe ECS::Singleton do
  it "exists on every entity" do
    world = ECS::World.new
    ent = world.new_entity.add(Pos.new(1, 1))
    ent.add(Speed.new(10, 10))
    world.new_entity.add(Config.new(100))
    ent.getConfig.value.should eq 100
  end

  it "can be changed on every entity" do
    world = ECS::World.new
    ent = world.new_entity.add(Pos.new(1, 1))
    ent.add(Speed.new(10, 10))
    world.new_entity.add(Config.new(100))
    ent.getConfig.value.should eq 100
    ent.update(Config.new(101))
    ent.getConfig.value.should eq 101
  end

  it "shouldn't be iterated" do
    world = ECS::World.new
    ent = world.new_entity
    ent.add(Pos.new(1, 1))
    ent.add(Speed.new(10, 10))
    world.new_entity.add(Config.new(100))
    count_entities(world).should eq 1
    world.of(Config).size.should eq 0
  end

  it "can be acquired from a world" do
    world = ECS::World.new
    expect_raises(Exception) { world.getConfig }
    world.getConfig?.should be_nil
    world.new_entity.add(Config.new(100))
    world.getConfig?.should be_truthy
    world.getConfig.value.should eq 100
    world.getConfig_ptr.value.value.should eq 100
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

describe ECS do
  it "don't trigger bug with iterating events" do
    world = ECS::World.new
    1025.times { |i|
      ent = world.new_entity.add(Pos.new(0, 0))
      ent = world.new_entity.add(Speed.new(0, 0))
      ent = world.new_entity.add(Pos.new(0, 0)).add(Speed.new(0, 0))
    }
    sys1 = SystemGenerateEvent(TestEvent1).new(world, world.of(Pos))
    sys2 = SystemGenerateEvent(TestEvent2).new(world, world.of(Speed))
    sys3 = SystemGenerateEvent(TestEvent3).new(world, world.all_of([TestEvent1, TestEvent2]))
    sys4 = CountAllOf(TestEvent3).new(world)
    systems = ECS::Systems.new(world).add(sys1).add(sys2).add(sys3).add(sys4)
      .remove_singleframe(TestEvent1)
      .remove_singleframe(TestEvent2)
      .remove_singleframe(TestEvent3)
    systems.init
    systems.execute
    systems.execute
    systems.execute
  end
end

@[ECS::Multiple]
record Changer < ECS::Component, dx : Int32, dy : Int32

@[ECS::Multiple]
@[ECS::SingleFrame]
record Request < ECS::Component, dx : Int32, dy : Int32

class ProcessRequests < ECS::System
  def filter(world)
    world.all_of([Request, Pos])
  end

  def process(entity)
    pos = entity.getPos
    req = entity.getRequest
    entity.set(Pos.new(pos.x + req.dx, pos.y + req.dy))
  end
end

class ProcessChangers < ECS::System
  def filter(world)
    world.all_of([Changer, Pos])
  end

  def process(entity)
    pos = entity.getPos
    req = entity.getChanger
    entity.set(Pos.new(pos.x + req.dx, pos.y + req.dy))
  end
end

class GenerateRequests < ECS::System
  def initialize(@world, @list : Array(Int32))
  end

  def filter(world)
    world.of(Pos)
  end

  def process(entity)
    @list.each { |x| entity.add(Request.new(x, 0)) }
  end
end

describe ECS::Multiple do
  it "can be added" do
    world = ECS::World.new
    ent = world.new_entity
    ent.has?(Changer).should be_false
    ent.add(Pos.new(0, 0))
    ent.has?(Changer).should be_false
    ent.add(Changer.new(1, 1))
    ent.has?(Changer).should be_true
    ent.add(Changer.new(2, 2))
    ent.has?(Changer).should be_true
  end

  it "can be added and then all removed" do
    world = ECS::World.new
    ent = world.new_entity
    ent.add(Pos.new(0, 0))
    ent.add(Changer.new(1, 1))
    ent.add(Changer.new(2, 2))
    ent.has?(Changer).should be_true
    ent.remove(Changer)
    ent.has?(Changer).should be_false
    expect_raises(Exception) { ent.remove(Changer) }
  end

  it "can be iterated" do
    world = ECS::World.new
    ent = world.new_entity
    ent.add(Pos.new(0, 0))
    ent.add(Changer.new(1, 1))
    ent.add(Changer.new(2, 2))
    world.of(Changer).size.should eq 2
    world.of(Pos).size.should eq 1
  end

  it "can be iterated after removal" do
    world = ECS::World.new
    ent = world.new_entity
    ent.add(Pos.new(0, 0))
    ent.add(Changer.new(1, 1))
    ent.add(Changer.new(2, 2))
    world.of(Changer).size.should eq 2
    ent.remove(Changer)
    world.of(Changer).size.should eq 0
  end

  it "can be iterated in combination with usual components" do
    world = ECS::World.new
    ent = world.new_entity
    ent.add(Pos.new(0, 0))
    ent.add(Changer.new(1, 1))
    ent.add(Changer.new(2, 2))
    ent = world.new_entity
    ent.add(Changer.new(3, 3))
    ent = world.new_entity
    ent.add(Changer.new(4, 4))
    world.any_of([Changer, Pos]).size.should eq 4
    world.any_of([Pos, Changer]).size.should eq 4
    world.all_of([Changer, Pos]).size.should eq 2
    world.all_of([Pos, Changer]).size.should eq 2
  end

  it "can be iterated in combination with usual components #2" do
    world = ECS::World.new
    ent = world.new_entity
    ent.add(Pos.new(0, 0))
    ent.add(Changer.new(1, 1))
    ent.add(Changer.new(2, 2))
    ent.add(Speed.new(0, 0))
    ent = world.new_entity
    ent.add(Changer.new(3, 3))
    ent.add(Speed.new(0, 0))
    ent = world.new_entity
    ent.add(Changer.new(4, 4))
    ent.add(Speed.new(0, 0))
    world.of(Speed).any_of([Pos, Changer]).size.should eq 4
  end

  it "can't be iterated when several of them present in filter" do
    world = ECS::World.new
    expect_raises(Exception) { world.any_of([Changer, Request]) }
    expect_raises(Exception) { world.all_of([Changer, Request]) }
    expect_raises(Exception) { world.of(Changer).of(Request) }
    expect_raises(Exception) { world.any_of([Changer, Pos]).any_of([Request, Speed]) }
    world.of(Changer).exclude(Request).size.should eq 0
  end

  it "can be processed with systems" do
    world = ECS::World.new
    systems = ECS::Systems.new(world)
      .add(ProcessChangers.new(world))
    systems.init
    ent = world.new_entity
    ent.add(Pos.new(0, 0))
    ent.add(Changer.new(1, 0))
    ent.add(Changer.new(10, 0))
    systems.execute
    ent.getPos.x.should eq 11
    systems.execute
    ent.getPos.x.should eq 22
  end

  it "can be processed with systems (single-frame)" do
    world = ECS::World.new
    systems = ECS::Systems.new(world)
      .add(GenerateRequests.new(world, [10, 1]))
      .add(ProcessRequests.new(world))
      .remove_singleframe(Request)
    systems.init
    ent = world.new_entity
    ent.add(Pos.new(0, 0))
    ent.add(Changer.new(1, 0))
    ent.add(Changer.new(10, 0))
    systems.execute
    ent.getPos.x.should eq 11
    systems.execute
    ent.getPos.x.should eq 22
    systems.execute
    ent.getPos.x.should eq 33
  end

  it "can be processed with systems (single-frame) when requests come from different systems" do
    world = ECS::World.new
    systems = ECS::Systems.new(world)
      .add(GenerateRequests.new(world, [10]))
      .add(ProcessRequests.new(world))
      .remove_singleframe(Request)
      .add(GenerateRequests.new(world, [1]))
    systems.init
    ent = world.new_entity
    ent.add(Pos.new(0, 0))
    systems.execute
    ent.getPos.x.should eq 10
    systems.execute
    ent.getPos.x.should eq 21
    systems.execute
    ent.getPos.x.should eq 32
  end
end

describe ECS do
  it "don't trigger bug with iterating after removal" do
    world = ECS::World.new
    systems = ECS::Systems.new(world)
      .add(ECS::RemoveAllOf.new(world, Speed))
      .add(ECS::RemoveAllOf.new(world, Pos))
    systems.init

    ent1 = world.new_entity
    ent1.add(Pos.new(1, 1))
    ent1.add(Speed.new(0, 0))

    ent2 = world.new_entity
    ent2.add(Pos.new(2, 2))
    ent2.add(Speed.new(0, 0))

    ent3 = world.new_entity
    ent3.add(Pos.new(3, 3))
    ent3.add(Speed.new(0, 0))
    world.of(Speed).size.should eq 3
    ent1.remove(Pos)
    ent3.remove(Pos)
    world.of(Pos).first?.not_nil!.getPos.should eq Pos.new(2, 2)
  end
end

describe ECS::World do
  it "can found single entity without filter" do
    world = ECS::World.new
    world.component_exists?(Pos).should be_false
    ent = world.new_entity.add(Pos.new(1, 1))
    world.component_exists?(Pos).should be_true
    ent.destroy
    world.component_exists?(Pos).should be_false
  end

  it "can iterate on a single component without filter" do
    world = ECS::World.new
    world.query(Pos).size.should eq 0
    ent = world.new_entity.add(Pos.new(1, 1))
    world.new_entity.add(Pos.new(2, 2))
    world.query(Pos).size.should eq 2
    ent.destroy
    world.query(Pos).size.should eq 1
  end

  it "can show stats" do
    world = ECS::World.new
    world.stats.should eq Hash(String, Int32).new
    ent = world.new_entity.add(Pos.new(1, 1))
    ent.add(Speed.new(2, 2))
    ent = world.new_entity.add(Pos.new(1, 1))
    world.stats.should eq({"Speed" => 1, "Pos" => 2})
  end

  it "raises on reuse of deleted entities" do
    world = ECS::World.new
    ent = world.new_entity.add(Pos.new(1, 1))
    ent.remove(Pos)
    expect_raises(Exception) { ent.add(Speed.new(1, 1)) }
  end

  it "don't hangs if component is just added during iterating on it" do
    world = ECS::World.new
    world.new_entity.add(Pos.new(1, 1))
    world.new_entity.add(Pos.new(2, 2))
    iter = 0
    world.of(Pos).each do |ent|
      pos = ent.getPos
      world.new_entity.add(pos) if world.entities_count < 5
      iter += 1
      raise "hangs up" if iter > 10
    end
  end

  it "don't hangs if component is deleted and added during iterating on it" do
    world = ECS::World.new
    world.new_entity.add(Pos.new(1, 1))
    world.new_entity.add(Pos.new(2, 2))
    iter = 0
    world.of(Pos).each do |ent|
      pos = ent.getPos
      ent.remove(Pos)
      world.new_entity.add(pos)
      iter += 1
      raise "hangs up" if iter > 10
    end
  end

  it "don't hangs if component is replaced during iterating on it" do
    world = ECS::World.new
    world.new_entity.add(Pos.new(1, 1))
    world.new_entity.add(Pos.new(2, 2))
    iter = 0
    world.of(Pos).each do |ent|
      pos = ent.getPos
      ent.replace(Pos, Speed.new(pos.x, pos.y))
      speed = ent.getSpeed
      ent.replace(Speed, Pos.new(speed.vx, speed.vy))
      iter += 1
      raise "hangs up" if iter > 10
    end
  end
end

record TestCallbacks < ECS::Component, name : String do
  class_getter added = [] of String
  class_getter deleted = [] of String

  def when_added(entity)
    @@added << @name
  end

  def when_removed(entity)
    @@deleted << @name
  end
end

@[ECS::Multiple]
record TestCallbacksMultiple < ECS::Component, name : String do
  class_getter added = [] of String
  class_getter deleted = [] of String

  def when_added(entity)
    @@added << @name
  end

  def when_removed(entity)
    @@deleted << @name
  end
end

@[ECS::SingleFrame]
record TestCallbacksSingleFrame < ECS::Component, name : String do
  class_getter added = [] of String
  class_getter deleted = [] of String

  def when_added(entity)
    @@added << @name
  end

  def when_removed(entity)
    @@deleted << @name
  end
end

describe ECS do
  describe "callbacks" do
    it "when_added called when component is added" do
      world = ECS::World.new
      TestCallbacks.added.clear
      world.new_entity.add(Pos.new(1, 1)).add(TestCallbacks.new("first"))
      world.new_entity.add(TestCallbacks.new("second"))
      TestCallbacks.added.should eq ["first", "second"]
    end

    it "when_removed called when component is removed" do
      world = ECS::World.new
      TestCallbacks.deleted.clear
      ent2 = world.new_entity.add(TestCallbacks.new("second"))
      ent1 = world.new_entity.add(Pos.new(1, 1)).add(TestCallbacks.new("first"))
      ent1.destroy
      ent2.remove(TestCallbacks)
      TestCallbacks.deleted.should eq ["first", "second"]
    end

    it "when_removed called when world is cleared" do
      world = ECS::World.new
      TestCallbacks.deleted.clear
      ent1 = world.new_entity.add(Pos.new(1, 1)).add(TestCallbacks.new("first"))
      ent2 = world.new_entity.add(TestCallbacks.new("second"))
      world.delete_all(with_callbacks: true)
      TestCallbacks.deleted.should eq ["first", "second"]

      TestCallbacks.deleted.clear
      ent1 = world.new_entity.add(Pos.new(1, 1)).add(TestCallbacks.new("first"))
      ent2 = world.new_entity.add(TestCallbacks.new("second"))
      world.delete_all(with_callbacks: false)
      TestCallbacks.deleted.should be_empty
    end

    it "when_added and when_removed works with singleframe components" do
      world = ECS::World.new
      TestCallbacksSingleFrame.deleted.clear
      TestCallbacksSingleFrame.added.clear
      systems = ECS::Systems.new(world).remove_singleframe(TestCallbacksSingleFrame)
      systems.init
      ent1 = world.new_entity.add(Pos.new(1, 1)).add(TestCallbacksSingleFrame.new("first"))
      ent2 = world.new_entity.add(TestCallbacksSingleFrame.new("second"))
      systems.execute
      TestCallbacksSingleFrame.added.should eq ["first", "second"]
      TestCallbacksSingleFrame.deleted.should eq ["first", "second"]
    end

    it "when_added and when_removed works with multiple components" do
      world = ECS::World.new
      TestCallbacksMultiple.deleted.clear
      TestCallbacksMultiple.added.clear
      systems = ECS::Systems.new(world).remove_singleframe(TestCallbacksMultiple)
      systems.init
      ent2 = world.new_entity.add(Pos.new(1, 1)).add(TestCallbacksMultiple.new("second"))
      ent1 = world.new_entity.add(TestCallbacksMultiple.new("first"))
      ent2.add(TestCallbacksMultiple.new("third"))
      ent1.destroy
      ent2.remove(TestCallbacksMultiple)
      TestCallbacksMultiple.added.should eq ["second", "first", "third"]
      TestCallbacksMultiple.deleted.should eq ["first", "second", "third"]
    end
  end
end

describe ECS::World do
  it "can be serialized and deserialized when empty" do
    world = ECS::World.new
    io = IO::Memory.new
    world.encode io
    total_size = io.pos
    world2 = ECS::World.new
    io.rewind
    world2.decode io
    io.pos.should eq total_size
    puts "serialization of empty world: #{total_size}"
  end

  it "can be serialized and deserialized" do
    world = ECS::World.new
    io = IO::Memory.new
    100.times do
      ent = world.new_entity.add(Pos.new(1, 1))
      ent.add(Speed.new(3, 3)) if rand < 0.5
      ent.add(Name.new("Test")) if rand < 0.5
    end
    50.times do
      world.of(Pos).sample.destroy
    end
    100.times do
      ent = world.new_entity.add(Pos.new(1, 1))
      ent.add(Speed.new(3, 3)) if rand < 0.5
      ent.add(Name.new("Test")) if rand < 0.5
    end
    50.times do
      world.of(Pos).sample.destroy
    end
    world.encode io
    total_size = io.pos
    old_stats = world.stats
    old_values = world.query(Pos).to_a.map do |ent|
      {ent.getPos?, ent.getSpeed?, ent.getName?}
    end

    world2 = ECS::World.new
    io.rewind
    world2.decode io
    io.pos.should eq total_size
    world.stats.should eq old_stats
    values = world.query(Pos).to_a.map do |ent|
      {ent.getPos?, ent.getSpeed?, ent.getName?}
    end
    values.should eq old_values
    puts "serialization size: #{total_size}"
  end

  pending "isn't broken after deserialization" do
    world = ECS::World.new
    io = IO::Memory.new
    100.times do
      ent = world.new_entity.add(Pos.new(1, 1))
      ent.add(Speed.new(3, 3)) if rand < 0.5
      ent.add(Name.new("Test")) if rand < 0.5
    end
    50.times do
      world.of(Pos).sample.destroy
    end
    100.times do
      ent = world.new_entity.add(Pos.new(1, 1))
      ent.add(Speed.new(3, 3)) if rand < 0.5
      ent.add(Name.new("Test")) if rand < 0.5
    end
    50.times do
      world.of(Pos).sample.destroy
    end
    world.encode io

    world2 = ECS::World.new
    io.rewind
    world2.decode io

    100.times do
      ent = world2.new_entity.add(Pos.new(1, 1))
      ent.add(Speed.new(3, 3)) if rand < 0.5
      ent.add(Name.new("Test")) if rand < 0.5
    end
    50.times do
      world2.of(Pos).sample.destroy
    end
    100.times do
      ent = world2.new_entity.add(Pos.new(1, 1))
      ent.add(Speed.new(3, 3)) if rand < 0.5
      ent.add(Name.new("Test")) if rand < 0.5
    end
    50.times do
      world2.of(Pos).sample.destroy
    end
  end
end

ECS.debug_stats
