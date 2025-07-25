

## What next

### Api 
We need to add something that allows us to create entities.
Something like:

```zig
fn makeEntity(self: Self, comp: anytype) {
  inline for (components) |c| { 
    comp = try self.allocComponent(c)
  }
  // make entity out of those components
}
```

### Memory

Another thing we need is to thing about storage.

Scene can hold all entities - that is fine

Scene can hold components but it cannot be an array 

Basically:
  When we dealloc entity we have to dealloc all the components too:
    - in this sense we can thing of something like this.
      `component { header: Header, comp: Comp }`
    - Then we return the pointer to component
    - when we deallocate we need to substract pointer so that we can remove both comp and header.
    - we will use header information to know what is the size of the component
    - now what about alignment ? - we cannot guarantee that component is directly after header
      we need to take alignment into account

But the idea is that scene holds the entities 
and then those entities are responsible for freeing components with pointer magic.


### Iterating components

We need to think of a system for easily iterating over components.
That means we have to have a way to quickly map over archetypes.

Mostly we need to be able to 
a) identify all entities holding needed components
b) access those components
c) figure out how it will interact with lua

### Lua components

So we need a way to add lua scripting into this somehow.
Like lua should be allowed to make entities.
And it should be allowed to make components, I think.
But how do we integrate it is another question.
We need native systems and native components so that we can interop with
raylib.

### Reallocating archetypes

If some component is added or removed we need to move entity to another archetype.
Technically as scene has all entities on the heap. The archetype storage
can just simply be a map of []component_ids to pointers to entities.

