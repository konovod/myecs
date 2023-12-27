require "../src/yaml"

record Unsupported < ECS::Component, x : Int32, y : Int32
record Supported < ECS::YAMLComponent, x : Int32, y : Int32

it "serialize world to yaml" do
  world = ECS::World.new
  world.new_entity.add(Supported.new(1, 2))
  world.new_entity.add(Unsupported.new(3, 4))
  world.to_yaml.should eq "---
Entity0:
- type: Supported
  x: 1
  y: 2
Entity1: []
"
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
