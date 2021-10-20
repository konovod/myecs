require "./spec_helper"

record Pos < ECS::Component, x : Int32, y : Int32 do
  def change_x(value)
    @x = value
  end
end
record Speed < ECS::Component, vx : Int32, vy : Int32
record Name < ECS::Component, name : String

@[ECS::SingleFrame]
record TestEvent < ECS::Component
@[ECS::SingleFrame]
record TestEvent2 < ECS::Component

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
    typeof(ent.getPos).should eq (Pos)
    typeof(ent.getPos?).should eq (Pos | Nil)
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
    count_entities(world.of(Pos)).should eq 1
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
    count_entities(filter).should eq 0
    ent2.add(Speed.new(1, 1))
    count_entities(filter).should eq 1
    ent2.add(Pos.new(1, 1))
    ent2.remove(Speed)
    count_entities(filter).should eq 0
  end

  it "can iterate using filters with all_of" do
    world = ECS::World.new
    ent = world.new_entity
    ent2 = world.new_entity
    ent.add(Pos.new(1, 1))
    ent2.add(Pos.new(1, 1))
    count_entities(world.all_of([Pos, Speed])).should eq 0
    ent2.add(Speed.new(1, 1))
    count_entities(world.all_of([Pos, Speed])).should eq 1
    count_entities(world.all_of([Pos])).should eq 2
    count_entities(world.all_of([Pos, Name])).should eq 0
    count_entities(world.all_of([Name])).should eq 0
  end
  it "can iterate using filters with any_of" do
    world = ECS::World.new
    world.new_entity.add(Pos.new(1, 1))
    count_entities(world.any_of([Name, Speed])).should eq 0
    world.new_entity.add(Pos.new(1, 1)).add(Speed.new(1, 1))
    world.new_entity.add(Speed.new(1, 1))
    count_entities(world.any_of([Pos, Speed])).should eq 3
    count_entities(world.any_of([Name, Pos])).should eq 2
  end

  it "any_of works with single item" do
    world = ECS::World.new
    world.new_entity.add(Pos.new(1, 1))
    count_entities(world.any_of([Pos])).should eq 1
    world.new_entity.add(Pos.new(1, 1)).add(Speed.new(1, 1))
    world.new_entity.add(Speed.new(1, 1))
    count_entities(world.any_of([Pos])).should eq 2
    count_entities(world.any_of([Name])).should eq 0
  end

  it "can filter using exclude" do
    world = ECS::World.new
    world.new_entity.add(Pos.new(1, 1))
    world.new_entity.add(Pos.new(1, 1)).add(Speed.new(1, 1))
    world.new_entity.add(Speed.new(1, 1))
    count_entities(world.of(Pos).exclude(Speed)).should eq 1
    count_entities(world.exclude([Speed])).should eq 1
    count_entities(world.exclude(Name)).should eq 3
    count_entities(world.exclude([Name, Pos])).should eq 1
  end
  it "can filter using select" do
    world = ECS::World.new
    world.new_entity.add(Pos.new(1, 1))
    world.new_entity.add(Pos.new(1, -1)).add(Speed.new(1, 1))
    world.new_entity.add(Speed.new(1, 2))
    count_entities(world.of(Pos).select { |ent| ent.getPos.y > 0 }).should eq 1
    expect_raises(Exception) { count_entities(world.new_filter.select { |ent| ent.getPos.y > 0 }) }
  end

  it "can found single entity" do
    world = ECS::World.new
    world.of(Pos).find_entity?.should eq nil
    ent = world.new_entity.add(Pos.new(1, 1))
    world.of(Pos).find_entity?.should eq ent
    ent.destroy
    world.of(Pos).find_entity?.should eq nil
  end

  it "can add component of runtime type" do
    world = ECS::World.new
    ent = world.new_entity
    event = rand < 0.5 ? Pos.new(1, 1) : Speed.new(2, 2)
    ent.add(event)
    world.any_of([Pos, Speed]).find_entity?.should eq ent
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

  it "delete single frame events" do
    world = ECS::World.new
    filter = world.of(TestEvent)
    ent = world.new_entity.add(TestEvent.new)
    count_entities(filter).should eq 1
    filter2 = world.of(Pos)
    ent2 = world.new_entity.add(Pos.new(2, 2))
    count_entities(filter2).should eq 1

    world.clear_single_frame
    count_entities(filter).should eq 0
    count_entities(filter2).should eq 1
  end
end

@[ECS::SingleFrame]
record TestEvent1 < ECS::Component
@[ECS::SingleFrame]
record TestEvent2 < ECS::Component
@[ECS::SingleFrame]
record TestEvent3 < ECS::Component

class ReplaceEventsSystem(EventFrom, EventTo) < ECS::System
  def filter(world)
    world.of(EventFrom)
  end

  def process(entity)
    entity.add(EventTo.new)
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
  it "deleted in correct order" do
    world = ECS::World.new
    sys1 = ReplaceEventsSystem(TestEvent2, TestEvent3).new(world)
    sys2 = ReplaceEventsSystem(TestEvent1, TestEvent2).new(world)
    sys3 = GenerateEventsSystem(TestEvent1).new(world)
    systems = ECS::Systems.new(world).add(sys1).add(sys2).add(sys3)
    ev1_check = world.of(TestEvent1)
    ev2_check = world.of(TestEvent2)
    ev3_check = world.of(TestEvent3)
    systems.init
    sys3.active = true
    systems.execute
    world.clear_single_frame
    ev1_check.find_entity?.should be_truthy
    ev2_check.find_entity?.should be_falsey
    ev3_check.find_entity?.should be_falsey
    sys3.active = false
    systems.execute
    ev1_check.find_entity?.should be_falsey
    ev2_check.find_entity?.should be_truthy
    ev3_check.find_entity?.should be_falsey
    systems.execute
    ev1_check.find_entity?.should be_falsey
    ev2_check.find_entity?.should be_falsey
    ev3_check.find_entity?.should be_truthy
    systems.execute
    ev1_check.find_entity?.should be_falsey
    ev2_check.find_entity?.should be_falsey
    ev3_check.find_entity?.should be_falsey
  end

  it "deleted in correct order #2" do
    world = ECS::World.new
    sys1 = ReplaceEventsSystem(Pos, TestEvent1).new(world)
    sys2 = ReplaceEventsSystem(TestEvent1, TestEvent2).new(world)
    systems = ECS::Systems.new(world).add(sys1).add(sys2)
    ev1_check = world.of(TestEvent1)
    ev2_check = world.of(TestEvent2)
    world.new_entity.add(Pos.new(0, 0))
    world.new_entity.add(Pos.new(1, 1))
    systems.init
    systems.execute
    count_entities(ev1_check).should eq 2
    count_entities(ev2_check).should eq 2
    systems.execute
    count_entities(ev1_check).should eq 2
    count_entities(ev2_check).should eq 2
    sys1.active = false
    systems.execute
    count_entities(ev1_check).should eq 0
    count_entities(ev2_check).should eq 0
  end

  it "deleted in correct order when generated in init" do
    world = ECS::World.new
    sys1 = GenerateEventsInInitSystem(TestEvent1).new(world)
    sys2 = ReplaceEventsSystem(TestEvent1, TestEvent2).new(world)
    systems = ECS::Systems.new(world).add(sys1).add(sys2)
    ev1_check = world.of(TestEvent1)
    ev2_check = world.of(TestEvent2)
    systems.init
    ev1_check.find_entity?.should be_truthy
    ev2_check.find_entity?.should be_falsey
    systems.execute
    world.clear_single_frame
    ev1_check.find_entity?.should be_falsey
    ev2_check.find_entity?.should be_truthy
    systems.execute
    world.clear_single_frame
    ev1_check.find_entity?.should be_falsey
    ev2_check.find_entity?.should be_falsey
  end
end

@[ECS::SingletonComponent]
record Config < ECS::Component, value : Int32

describe ECS::SingletonComponent do
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
    count_entities(world.of(Config)).should eq 0
  end
end
