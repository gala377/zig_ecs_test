## Highlights

- Iterating making queries based in tuple of types.
- Exporting components to lua with derivation
- Accessing components from lua
- Writing systems in lua
- Hash is stored as integers in lua
- exposing a lot of fields to lua
- wrapper for slices 
- events - for now not exposed to lua 
- WithOut filter 
- yield-dispatch in lua 

## What next

- lockless multithreading of systems
- exposing native functions to lua.
  - something that will allow us to define func 
   `fn foo(s: Lua(String), n: Lua(isize), query: *Query({Button}))`
   and expose it lua as a `foo(string, integer)` that will return a
   value to lua by yield dispatch.

   This is for lua systems and lua scripts.

- system conditions
  - something like `system(func).run_if(cond)`

- creating components/entities in lua [[#Exposing constructors to lua]]
- exposing Commands to lua [[#Exposing constructors to lua]]
- Lua defined components - this one is hard and not sure how to do this yet.
  Kinda do actually, we can have a LuaComponent, that gets its id from lua and not from 
  its type. Its from lua implementation would be just getting the ref and toLua would 
  just be pushing the ref.
- exposing events in lua
- exposing methods to lua

### Lockless multithreading

Some things to consider except for doing graph coloring with systems.

We need to make sure that multiple queries do not affect each other.

Or that 2 systems that don't share components within their signature
cannot affect each other.

- anything that uses Game* directly conflicts with everything else

- commands use vtable_storage.createVTable which might allocate
  this means we might have to put a lock there.
  It should be fine though as again no 2 systems can use
  commands at the same time

- queries are the biggest problem
  - Creating query uses dynamic type id which is not guarded
    and will be a high contention point. 
    
    One solution would be to preinitialize it with conponent types
    that are in sets so that lookup does not create new id 
    meaning it will be always safe to use it.

  - iterating over query also uses dynamic id which again might be okay
    as long as we can make it so that the value is preinitialized.

    **This looks like the biggest problem so far**

  - if the cache doesn't have a query in it it will allocate and add
    to cache. Meaning that the cache might need to be guarded 
    as it can lead to data races.

- Id provider and dynamic id are shared and not guarded by mutex.
  But whenever we create a new entity they happen to be used.
  As long as we only use them from commands though it should be fine
  As no 2 systems that use commands can be executed at the same time.

- Resources are just components on singleton entity which means that
  we can treat them as normal components

- EventReader and EventWriter are conflicting but, because they are proxies
  we can get to their underlying resource.

- Event readers technically don't conflict with each other but it seems like
  a niche case. Probably not worth implementing. 

### Exposing more types to lua

For now the last 2 types that are exposable are structs and pointers to one element.
We could also try later to do enums and even later tagged unions but for now
we don't plan on supporting those.

Also StringHashMap and ArrayList would be useful, array list should be kinda easy
except how to identify it but other than that it is doable.


### Exposing constructors to lua

We already have fromLua function. What is left is to
integrate it with lua and also meningful errors for missing fields or wrong types.

Lua would need to have its own commands resource that is then
processed by the system in zig. 


This system would go through the entities that lua wants to create. 
That would probably be held by a ref or something like this ? 

Create those components by getting their id and looking up the fromLua function
from the vtable. And then creating them in the scene or global storage depending where
they have been allocated. 

All of those lua Commands could be implemented in lua itself we would just need to expose
`getSceneId` function to lua. So that we can create appropriate entity id.

The only problem is that now this is a resource that is lua defined? 
Tbf the resource can be zig defined but we would need a wrapper for it? 
Like it could be an arraylist of lua references, maybe? And then we have methods for it? 
Well we can make this special object like expose methods in lua

like: 

```lua
---@param commands Query<[Commands]>
function system(commandsq)
    local commands = query.single(commandsq)
    commands:globalEntity {
      Button.new { title = "hello", visible = true, clicked = false },
      ButtonClose.new {},
    }
end
```

This means we need to expose a `new` function that takes a table.
Maybe this function can verify if all fields have been provided and
then it will add component id. 

That means that this will have to also be an interface for lua components
in the future, we need to generate `new` method for them that will add their id to them.
So something like so

```lua
function Component()
  local id = newGlobalId()

  local builder = {
    comp_id = id,
  }

  function builder.new(args) 
    args.comp_id = id
    return args
  end

  return builder
end
```

So now when you pass a builder to `query` when building a system it can still use the 
comp_id to retrieve it, but when you create it using `new` we can use comp_id to
store it. 

Those components will have to not be stored by pointer but by lua ref that 
has to be pushed, so they do require special handling, which is a bit annoying.
We cannot store them separately. Well we could like store optional
ref in vtable I guess? maybe use union of ref and pointer? 
its a bit of a mystery how to handle zig and lua components at the same time.

All below does not need to be considered
====================================

This can only be allowed for subset of components where
all nonnullable fields can be created from lua.

Which boils down to is every primitive type + strings.
Structs of primitive types.
Nullable types of convertible types.

Later we could technically even do enums and tagged unions.

It means for now that we just need to add generated command like
`fromLua(state: lua.State, allocator: std.mem.Allocator) !Self`.

If a component has non-default, no-lua constructible field it should probably
just throw runtime error and it should be fine.

### Lua components

We can just hold them as refs, the problem is their identity.
Meaning hash of them.
We might provide some function like `component` in lua that generates
a hash for a component and then the component is held as ref.
The problem is how ti generate this hash, we can expose a function to lua
from our runtime that has Game as context and can use the same has function.
But we somehow need to get like a unique name for the component. Maybe UUID? 
Maybe there is some way to get them deterministically for later saving of
a game state?

### Control over system execution 

Things like system groups or anything like that.
Something that would allow us to define dependencies between systems.
