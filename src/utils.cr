class LinkedList
  @array : Array(Int32)
  @root = 0

  def initialize(@count : Int32)
    # initialize with each element pointing to next
    @array = Array(Int32).new(@count) { |i| i + 1 }
  end

  def next_item
    result = @root
    raise "linked list empty" if result >= @count
    @root = @array[@root]
    result
  end

  def release(item : Int32)
    @array[item] = @root
    @root = item
  end

  def resize(new_size)
    raise "shrinking list isn't supported" if new_size < @count
    (new_size - @count).times do |i|
      @array << i + @count + 1
    end
    @count = new_size
  end

  def clear
    @count.times do |i|
      @array[i] = i + 1
    end
    @root = 0
  end
end

class Queue(T)
  @stub : Deque(T)

  def initialize(size)
    @stub = Deque(T).new(size)
  end

  def push(item : T)
    @stub.push item
  end

  def pop : T?
    @stub.shift
  end

  def empty?
    @stub.empty?
  end

  def peek : T?
    @stub[0]
  end
end
