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



