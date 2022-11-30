# Benchmark

This app defines a set of mix tasks to benchmark the performance of arbitrary
plug-compatible web servers. 

## Usage

### Generating Raw Benchmark Data

The following will run the complete benchmark suite against either Bandit or
Cowboy, dynamically installing the corresponding mix package from the given GitHub treeish:

```
> mix benchmark [server_def]*
```

where `server_def` is one or more of:

* `bandit` to run against a local install of Bandit at `../bandit`
* `bandit@ref` to run against Bandit, as of the given `ref` on GitHub
* `cowboy` to run against Plug.Cowboy's `master` ref
* `cowboy@ref` to run against Plug.Cowboy, as of the given `ref` on GitHub

Output will be placed in `http-benchmark.csv`, which will be overwritten if present.

### Generating Comparative Benchmark Data

The following will run the complete benchmark suite against two servers, and
provide output indicating which are faster / slower on each test scenario. `server_def` is as above.

```
> mix benchmark.compare <server_def_a> <server_def_b>
```

Output will be placed in `http-benchmark.csv`, which will be overwritten if present.

### Running via Docker

To run these tests on large cloud boxes for the purposes of larger benchmarks,
do the following:

1. Set up a giant box on DO or equivalent (use an image that has docker included)
2. Put the following in a Dockerfile on the box:
    ```
    FROM elixir
    WORKDIR /app
    RUN apt-get update
    RUN apt-get install -y nghttp2
    RUN git clone https://github.com/mtrudel/benchmark
    WORKDIR /app/benchmark
    RUN mix local.hex —force
    RUN mix local.rebar —force
    RUN mix deps.get
    CMD mix benchmark.compare -—huge cowboy bandit@main
    ```
3. Run like
    ```
    docker build -t build .
    docker run -d build
    docker logs -f <id>
    docker cp -a <id>:/apps .
    scp the output files
    ```
