# Tests
I'm comparing it with other ECS with some "realistic" scenario - creating world with 1_000_000 entities (with 100 component types), adding and removing components in it, iterating over components, replacing components with another etc.
You can see I'm not actually beating them in all areas (I'm slower in access but much faster in creation), but my ECS looks fast enough for me. What is I'm proud - 0.0B/op for all operations (after initial growth of pools)

## my ECS:
Compilation time (in release mode): 
```
real    0m30.592s
user    0m29.234s
sys     0m1.703s
```
Results:
```
***********************************************
              create empty world   8.34k (119.93µs) (± 5.61%)   484kB/op          fastest
          create benchmark world   5.68  (176.13ms) (± 8.67%)  1.02GB/op  1468.61× slower
create and clear benchmark world   4.66  (214.68ms) (± 5.40%)  1.02GB/op  1790.11× slower
***********************************************
                   EmptySystem 182.15M (  5.49ns) (± 2.51%)  0.0B/op        fastest
             EmptyFilterSystem  40.55M ( 24.66ns) (± 0.81%)  0.0B/op   4.49× slower
SystemAddDeleteSingleComponent  37.91M ( 26.38ns) (± 0.77%)  0.0B/op   4.81× slower
 SystemAddDeleteFourComponents   3.11M (321.07ns) (± 0.47%)  0.0B/op  58.48× slower
         SystemAskComponent(0) 143.23M (  6.98ns) (± 1.20%)  0.0B/op   1.27× slower
         SystemAskComponent(1) 139.83M (  7.15ns) (± 1.30%)  0.0B/op   1.30× slower
         SystemGetComponent(0) 121.21M (  8.25ns) (± 1.28%)  0.0B/op   1.50× slower
         SystemGetComponent(1) 111.17M (  9.00ns) (± 3.95%)  0.0B/op   1.64× slower
   SystemGetSingletonComponent 130.97M (  7.64ns) (± 1.19%)  0.0B/op   1.39× slower
 IterateOverCustomFilterSystem  75.59M ( 13.23ns) (± 1.17%)  0.0B/op   2.41× slower
***********************************************
         SystemCountComp1 297.24  (  3.36ms) (± 0.54%)  0.0B/op        fastest
        SystemUpdateComp1 117.62  (  8.50ms) (± 0.27%)  0.0B/op   2.53× slower
SystemUpdateComp1UsingPtr 242.48  (  4.12ms) (± 0.33%)  0.0B/op   1.23× slower
       SystemReplaceComps  41.23  ( 24.25ms) (± 0.14%)  0.0B/op   7.21× slower
         SystemPassEvents  32.59  ( 30.68ms) (± 0.37%)  0.0B/op   9.12× slower
***********************************************
         FullFilterSystem 169.08  (  5.91ms) (± 0.21%)  0.0B/op   1.76× slower
    FullFilterAnyOfSystem 125.96  (  7.94ms) (± 0.21%)  0.0B/op   2.36× slower
      SystemComplexFilter 297.23  (  3.36ms) (± 2.22%)  0.0B/op        fastest
SystemComplexSelectFilter 286.01  (  3.50ms) (± 0.81%)  0.0B/op   1.04× slower
```

## Entitas
https://github.com/spoved/entitas.cr

It worked with 1kk entities, but once added 100 components to the mix it started to crash. So it is benchmarked with half count of entities.

Fast components access (4ns vs 8ns), but slow in creation and updating.

Compilation time:
```
real    0m37.578s
user    0m39.594s
sys     0m1.891s
```
Results:
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

Compilation time:
```
real    0m20.507s
user    0m19.906s
sys     0m1.109s
```
Results:
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
