require "../src/yaml"

record Unsupported < ECS::Component, x : Int32, y : Int32
record Supported < ECS::YAMLComponent, x : Int32, y : Int32

it "serialize world to yaml" do
  world = ECS::World.new
  world.new_entity.add(Supported.new(1, 2))
  world.new_entity.add(Unsupported.new(3, 4))
  YAML.parse(world.to_yaml).to_s.should eq %q[{"Entity0" => [{"type" => "Supported", "x" => 1, "y" => 2}], "Entity1" => []}]
end

it "load world from yaml" do
  world1 = ECS::World.new
  world1.new_entity.add(Supported.new(1, 2))
  world1.new_entity.add(Unsupported.new(3, 4))
  yaml = world1.to_yaml
  world2 = ECS::World.from_yaml(yaml)
  world2.query(Supported).first.getSupported.should eq Supported.new(1, 2)
  world2.query(Unsupported).should be_empty
end

it "add entities from yaml" do
  world1 = ECS::World.new
  world1.new_entity.add(Supported.new(1, 2))
  world1.new_entity.add(Unsupported.new(3, 4))
  yaml = world1.to_yaml
  world2 = ECS::World.new
  world2.new_entity.add(Supported.new(10, 20))
  world2.add_yaml(yaml)
  world2.query(Supported).to_a.map(&.getSupported).should eq [Supported.new(10, 20), Supported.new(1, 2)]
  world2.query(Unsupported).should be_empty
end

record WithLink < ECS::YAMLComponent, link : ECS::Entity

it "keep links to entities" do
  world1 = ECS::World.new
  ent1 = world1.new_entity
  ent2 = world1.new_entity
  ent3 = world1.new_entity
  ent2.add(Supported.new(1, 2))
  ent1.add(WithLink.new(ent3))
  ent3.add(WithLink.new(ent2))
  yaml = world1.to_yaml
  world2 = ECS::World.new
  world2.new_entity.add(Supported.new(10, 20))
  world2.add_yaml(yaml)
  world2.query(WithLink).first.getWithLink.link.getWithLink.link.getSupported.should eq Supported.new(1, 2)
end
