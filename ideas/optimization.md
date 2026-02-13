# Optimization

## Lua use proxy

Currently when passing components to lua we need to create a new userdata
that is extremely wasteful as we just want to pass pointer that should not be
stored anyway. There are 2 solutions to this.

1. Pass lightuserdata and expose methods and fields as free functions

Instead of `foo.bar = { x = 1 }` we would need to do 
`Foo.fields.set_bar(foo, { x = 1 })`
for methods something like
`Foo.methods.getX(foo)`

It's not pretty but it puts no strain on lua at all as light userdata is just
a pointer. Also those pointers can be stored for the duration of the system.

2. Make ComponentProxy at the start of loop and just update pointer inside. 

Basically we create only one userdata and each `next` call we substitute the 
pointer inside it. This preserves all methods and fields access.

The only problem is that now proxy cannot be stored at all outside of the loop
iteration.

One solution to this is to have method like.

`ecs.component.copy(x)` which would create new user data so it can be stored.
That is also a fine solution.


## Incremental query cache

Right now whenever we create a new archetype (because of removal / addition of archetype) we 
invalidate all of the queries and need to create their cache once again.

This ofc doesn't make sense. Calculating query cache lazily makes sense but then again
i think we have to just have a generation counter.

Like whenever a cache a new archetype is introduced we increase generation of the 
entity storage. If the query has a cache entry with older generation that 
current one it should recompute the cache. 

Also, ideally it should only check the new archetypes. 
So we could make it so that each generation knows which archetype has been 
added in that generation. Which tbf.

Archetype count is kinda = to generation count know as we always add
archetypes to the end. So if we store the generation count
and then cache entry has generation count < current archetype count
we only need to consider archetypes 

`entity_storage.archetypes[generation_cout:]`

This should speed up cache re-computation.

The then we just store

`cache[query_type_id] = .{ .generation = entity_storage.archetypes.len, ... }`

And this should make this as efficient as possible



