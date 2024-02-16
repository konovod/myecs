require "./spec_helper"

describe ECS::EntitiesList do
  it "creates" do
    list = ECS::EntitiesList.new(32)
    32.times do |i|
      list.next_item.should eq i
    end
    expect_raises(ECS::Exception) { list.next_item }
  end

  it "can release elements" do
    list = ECS::EntitiesList.new(32)
    32.times do |i|
      list.next_item
    end
    list.release 12
    list.next_item.should eq 12
    list.release 11
    list.next_item.should eq 11
  end

  it "can release all elements" do
    list = ECS::EntitiesList.new(32)
    32.times do |i|
      list.next_item
    end
    32.times do |i|
      list.release(i)
    end
    32.times do |i|
      list.next_item.should eq i
    end
    expect_raises(ECS::Exception) { list.next_item }
    32.times do |i|
      list.release(31 - i)
    end
    32.times do |i|
      list.next_item.should eq 31 - i
    end
    expect_raises(ECS::Exception) { list.next_item }
  end

  it "can resize" do
    list = ECS::EntitiesList.new(32)
    32.times do |i|
      list.next_item
    end
    list.resize(64)
    32.times do |i|
      list.next_item.should eq i + 32
    end
    64.times do |i|
      list.release(i)
    end
    64.times do |i|
      list.next_item.should eq i
    end
    list.resize(128)
    64.times do |i|
      list.next_item.should eq i + 64
    end
    128.times do |i|
      list.release(127 - i)
    end
    128.times do |i|
      list.next_item.should eq 127 - i
    end
  end
end
