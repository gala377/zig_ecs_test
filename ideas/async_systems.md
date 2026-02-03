

Well i don't really have idea for async systems. 
This is more like async tasks.

The idea is simple 

```zig
fn my_task(e: Enemy) EnemyResult {
  // some expensive work that has to be done
}

fn resulting_system(args: Args(.{EnemyResult}), r: Resource(GameStats)) void {
  const e = args[0];
  r.get().update_stats(e);
}

fn my_system(c: Commands, q: *Query({Enemy})): void {
  const e = q.single();
  c.schedule_async(my_task, .{e})
   .on_completion(resulting_system);
}
```

So basically we can schedule any work to be executed asynchronously. 
And we will make it so that on completion a system will be called 
that accepts a result of this work and any additional parameters.


This easily extends to a lot of built in things like.

```zig

fn set_resource(comptime Res: type) System {
  return fn(args: Args(.{Res}), r: Resource(Res)) void {
    r.get().* = args[0];
  };
}

fn emit_event(comptime Event: type) System {
  return fn(args: Args(.{Event}), writer: EventWriter(Event)) void {
    writer.send(args[0]);
  };
}

fn spawn(comptime T: type, comptime components: anytype) System {
  return fn(args: Args(.{T}), c: Commands) void {
    _ = args;
    c.spawn(components);
  };
}

fn foo(c: Commands) void {
  c.schedule_async(my_task, .{})
    .on_completion(spawn(.{ Button { .x = 1, .y  = 10 } }));
  c.schedule_async(my_task, .{})
    .on_completion(emit_event(WorkDone));
}
```

So in general this gives us a lot of possibilities.

Ofc we would need to wrap task into something that maybe accepts cancellation token.
And we would need to have system that goes through all the tasks and sees which have been
finished.

It also makes sense to extend commands to allow scheduling any system to run by 
doing

```zig
// run system passing arguments (if any) to
// it as long as it has `Args` argument.
c.schedule_system(my_system, .{});
```
