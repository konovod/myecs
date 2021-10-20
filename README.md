# myecs

TODO: Write a description here

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     myecs:
       github: your-github-user/myecs
   ```

2. Run `shards install`

## Usage


see `bench_ecs.cr` for some examples, and `spec` folder for some more. Proper documentation and examples are planned, but not soon.

## Benchmarks
I'm comparing it with https://github.com/spoved/entitas.cr with some "realistic" scenarios - world with 1000000 entities, adding and removing components in it, iterating over components, replacing components with another etc.
You can see I'm not actually beating it in all areas (I'm much slower in access but much faster in creation), but my ECS looks fast enough for me. And what is I'm proud - 0.0B/op for all operations (after initial growth of pools)

my ECS:
```
***********************************************
              create empty world 108.74k (  9.20µs) (±10.72%)  200kB/op           fastest
          create benchmark world   2.26  (443.06ms) (± 9.95%)  284MB/op  48179.21× slower
create and clear benchmark world   2.16  (463.07ms) (± 4.73%)  284MB/op  50354.73× slower
***********************************************
                   EmptySystem 137.90M (  7.25ns) (± 2.00%)  0.0B/op         fastest
             EmptyFilterSystem  14.91M ( 67.07ns) (± 0.79%)  0.0B/op    9.25× slower
SystemAddDeleteSingleComponent   3.44M (290.35ns) (±16.52%)  0.0B/op   40.04× slower
 SystemAddDeleteFourComponents 726.69k (  1.38µs) (± 7.42%)  0.0B/op  189.76× slower
         SystemAskComponent(0)  42.82M ( 23.36ns) (± 1.03%)  0.0B/op    3.22× slower
         SystemAskComponent(1)  41.89M ( 23.87ns) (± 0.99%)  0.0B/op    3.29× slower
         SystemGetComponent(0)  45.44M ( 22.01ns) (± 2.62%)  0.0B/op    3.03× slower
         SystemGetComponent(1)  35.27M ( 28.35ns) (± 2.93%)  0.0B/op    3.91× slower
   SystemGetSingletonComponent  58.78M ( 17.01ns) (± 2.08%)  0.0B/op    2.35× slower
***********************************************
         SystemCountComp1  26.00  ( 38.46ms) (± 2.07%)  0.0B/op        fastest
        SystemUpdateComp1  11.36  ( 88.06ms) (± 1.39%)  0.0B/op   2.29× slower
SystemUpdateComp1UsingPtr  19.58  ( 51.06ms) (± 1.96%)  0.0B/op   1.33× slower
       SystemReplaceComp1   4.18  (239.06ms) (± 1.82%)  0.0B/op   6.22× slower
         SystemPassEvents   2.13  (469.74ms) (± 0.43%)  0.0B/op  12.21× slower
***********************************************
         FullFilterSystem  19.07  ( 52.43ms) (± 2.08%)  0.0B/op        fastest
    FullFilterAnyOfSystem   8.12  (123.19ms) (± 1.17%)  0.0B/op   2.35× slower
      SystemComplexFilter  18.01  ( 55.54ms) (± 1.80%)  0.0B/op   1.06× slower
SystemComplexSelectFilter  17.86  ( 56.01ms) (± 1.25%)  0.0B/op   1.07× slower
***********************************************
```
Entitas.cr:
```
***********************************************
              create empty world   2.50M (399.61ns) (±16.26%)  1.66kB/op             fastest
          create benchmark world   1.55  (643.32ms) (±11.33%)  1.57GB/op  1609878.49× slower
create and clear benchmark world   1.04  (958.39ms) (± 0.87%)  1.67GB/op  2398325.42× slower
***********************************************
                   EmptySystem 320.60M (  3.12ns) (± 1.66%)    0.0B/op         fastest
             EmptyFilterSystem 244.01M (  4.10ns) (± 4.15%)    0.0B/op    1.31× slower
SystemAddDeleteSingleComponent 537.81k (  1.86µs) (±11.43%)  1.59kB/op  596.13× slower
 SystemAddDeleteFourComponents 487.55k (  2.05µs) (±15.30%)   1.6kB/op  657.57× slower
         SystemAskComponent(0) 216.22M (  4.63ns) (± 4.59%)    0.0B/op    1.48× slower
         SystemAskComponent(1) 216.62M (  4.62ns) (± 1.87%)    0.0B/op    1.48× slower
         SystemGetComponent(0) 217.34M (  4.60ns) (± 4.63%)    0.0B/op    1.48× slower
         SystemGetComponent(1) 216.66M (  4.62ns) (± 3.60%)    0.0B/op    1.48× slower
***********************************************
         SystemCountComp1   8.96k (111.57µs) (± 0.21%)    0.0B/op          fastest
        SystemUpdateComp1  22.47  ( 44.50ms) (± 0.43%)    0.0B/op   398.85× slower
SystemUpdateComp1UsingPtr   7.07  (141.54ms) (± 0.99%)    0.0B/op  1268.61× slower
       SystemReplaceComp1   4.46  (224.01ms) (± 1.19%)  3.81MB/op  2007.79× slower
***********************************************
     FullFilterSystem 215.91M (  4.63ns) (± 2.55%)  0.0B/op     1.00× slower
FullFilterAnyOfSystem 216.47M (  4.62ns) (± 2.01%)  0.0B/op          fastest
  SystemComplexFilter  39.19k ( 25.52µs) (± 0.31%)  0.0B/op  5524.39× slower
```

## Development

Sadly I can't make `shards` work on Windows, so this is a mirror from a private repository, so there isn't even a history of commits.

## Contributors

- [Andrey Konovod](https://github.com/konovod) - creator and maintainer
