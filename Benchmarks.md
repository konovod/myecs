# Tests
I'm comparing it with other ECS with some "realistic" scenario - creating world with 1_000_000 entities (with 100 component types), adding and removing components in it, iterating over components, replacing components with another etc.
You can see I'm not actually beating them in all areas (I'm slower in access but much faster in creation), but my ECS looks fast enough for me. What is I'm proud - 0.0B/op for all operations (after initial growth of pools)

## my ECS:
```
***********************************************
              create empty world   8.79k (113.79µs) (± 5.56%)   484kB/op          fastest
          create benchmark world   5.30  (188.75ms) (±12.68%)  1.02GB/op  1658.69× slower
create and clear benchmark world   4.40  (227.10ms) (± 1.41%)  1.02GB/op  1995.69× slower
***********************************************
                   EmptySystem 161.99M (  6.17ns) (± 2.14%)  0.0B/op        fastest
             EmptyFilterSystem  35.11M ( 28.48ns) (± 1.41%)  0.0B/op   4.61× slower
SystemAddDeleteSingleComponent  33.49M ( 29.86ns) (± 2.79%)  0.0B/op   4.84× slower
 SystemAddDeleteFourComponents   2.66M (375.95ns) (± 1.04%)  0.0B/op  60.90× slower
         SystemAskComponent(0) 124.19M (  8.05ns) (± 2.22%)  0.0B/op   1.30× slower
         SystemAskComponent(1) 124.24M (  8.05ns) (± 2.14%)  0.0B/op   1.30× slower
         SystemGetComponent(0) 120.09M (  8.33ns) (± 3.09%)  0.0B/op   1.35× slower
         SystemGetComponent(1)  99.88M ( 10.01ns) (± 3.69%)  0.0B/op   1.62× slower
   SystemGetSingletonComponent 121.27M (  8.25ns) (± 2.82%)  0.0B/op   1.34× slower
 IterateOverCustomFilterSystem  77.77M ( 12.86ns) (± 2.89%)  0.0B/op   2.08× slower
***********************************************
         SystemCountComp1 245.30  (  4.08ms) (± 0.83%)  0.0B/op        fastest
        SystemUpdateComp1 110.80  (  9.03ms) (± 0.89%)  0.0B/op   2.21× slower
SystemUpdateComp1UsingPtr 208.47  (  4.80ms) (± 1.06%)  0.0B/op   1.18× slower
       SystemReplaceComps  32.71  ( 30.58ms) (± 0.79%)  0.0B/op   7.50× slower
         SystemPassEvents  28.22  ( 35.44ms) (± 0.98%)  0.0B/op   8.69× slower
***********************************************
         FullFilterSystem 143.00  (  6.99ms) (± 1.66%)  0.0B/op   1.70× slower
    FullFilterAnyOfSystem 101.43  (  9.86ms) (± 1.30%)  0.0B/op   2.40× slower
      SystemComplexFilter 112.97  (  8.85ms) (± 1.49%)  0.0B/op   2.15× slower
SystemComplexSelectFilter 243.34  (  4.11ms) (± 3.10%)  0.0B/op        fastest
```
## Entitas
https://github.com/spoved/entitas.cr

It worked with 1kk entities, but once added 100 components to the mix it started to crash. So it is benchmarked with half count of entities.

Fast components access (4ns vs 8ns), but slow in creation and updating.
```
***********************************************
              create empty world 350.73k (  2.85µs) (±17.52%)  13.0kB/op            fastest
          create benchmark world   2.00  (498.99ms) (±13.01%)  1.68GB/op  175012.30× slower
create and clear benchmark world   1.39  (721.14ms) (± 8.75%)  1.73GB/op  252925.92× slower
***********************************************
                   EmptySystem 327.74M (  3.05ns) (± 2.84%)    0.0B/op          fastest
             EmptyFilterSystem 258.61M (  3.87ns) (± 2.12%)    0.0B/op     1.27× slower
SystemAddDeleteSingleComponent 259.18k (  3.86µs) (±11.42%)  3.46kB/op  1264.51× slower
 SystemAddDeleteFourComponents 238.17k (  4.20µs) (±17.98%)  3.47kB/op  1376.08× slower
         SystemAskComponent(0) 221.77M (  4.51ns) (± 2.52%)    0.0B/op     1.48× slower
         SystemAskComponent(1) 222.47M (  4.49ns) (± 2.07%)    0.0B/op     1.47× slower
         SystemGetComponent(0) 218.50M (  4.58ns) (± 1.67%)    0.0B/op     1.50× slower
         SystemGetComponent(1) 221.06M (  4.52ns) (± 2.79%)    0.0B/op     1.48× slower
***********************************************
         SystemCountComp1  17.91k ( 55.84µs) (± 0.18%)    0.0B/op          fastest
        SystemUpdateComp1  28.80  ( 34.73ms) (± 0.82%)    0.0B/op   621.85× slower
SystemUpdateComp1UsingPtr  13.29  ( 75.25ms) (± 1.46%)    0.0B/op  1347.53× slower
       SystemReplaceComp1   8.82  (113.43ms) (± 1.18%)  1.91MB/op  2031.25× slower
***********************************************
     FullFilterSystem 241.66M (  4.14ns) (± 2.61%)  0.0B/op          fastest
FullFilterAnyOfSystem 241.46M (  4.14ns) (± 2.73%)  0.0B/op     1.00× slower
  SystemComplexFilter  78.15k ( 12.80µs) (± 0.26%)  0.0B/op  3092.29× slower
```

## Flecs
https://github.com/jemc/crystal-flecs.git

10x faster at iteration, 5x faster at updating, but other operations are significantly slower as it is archetype-based ecs.

Note that memory usage shows usage only on Crystal bindings side, not allocations inside Flecs itself.
```
              create empty world  81.10  ( 12.33ms) (± 0.78%)   1.0kB/op         fastest
          create benchmark world 287.02m (  3.48s ) (± 0.00%)  10.2MB/op  282.56× slower
create and clear benchmark world 264.29m (  3.78s ) (± 0.00%)  10.2MB/op  306.87× slower
***********************************************
                   EmptySystem 327.97k (  3.05µs) (± 0.62%)  0.0B/op    1.01× slower
             EmptyFilterSystem 329.99k (  3.03µs) (± 0.80%)  0.0B/op    1.00× slower
SystemAddDeleteSingleComponent 136.50k (  7.33µs) (± 0.40%)  0.0B/op    2.42× slower
 SystemAddDeleteFourComponents  78.04k ( 12.81µs) (± 0.33%)  0.0B/op    4.24× slower
              SystemCountComp1   8.84k (113.07µs) (± 0.56%)  0.0B/op   37.38× slower
             SystemUpdateComp1   1.15k (868.92µs) (± 0.44%)  0.0B/op  287.26× slower
***********************************************
            SystemReplaceComp1 372.83m (  2.68s ) (± 0.00%)  0.0B/op  fastest
***********************************************
SystemGetComponent(0) 294.91k (  3.39µs) (± 0.31%)  0.0B/op   1.01× slower
SystemGetComponent(1) 298.76k (  3.35µs) (± 0.44%)  0.0B/op        fastest
```
