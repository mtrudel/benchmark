# Benchmark

This app defines a set of mix tasks to benchmark the performance of arbitrary
plug-compatible web servers. 

## Usage

### Generating Raw Benchmark Data

The following will run the complete benchmark suite against a baseline and test
server (each of which may be any version of either Bandit or Cowboy):

```
> mix benchmark [options] <server_def_a> <server_def_b>
```

where `server_def` is one or more of:

* `bandit` to run against a local install of Bandit at `../bandit`
* `bandit@ref` to run against Bandit, as of the given `ref` on GitHub
* `cowboy` to run against Plug.Cowboy's `master` ref
* `cowboy@ref` to run against Plug.Cowboy, as of the given `ref` on GitHub

A summary Markdown document will be placed in `http-summary.md`

Detailed CSV output will be placed in `http-benchmark.csv`

Options include

* `--profile <tiny | normal | huge >` which profile size to run. Defaults to
`normal`
* `--protocol <protocol>` which protocol(s) to test. Defaults to `http/1.1,h2c`
* `--bigfile <true | false>` whether to use a large 10M file for upload tests. Defaults to false (wich uses a 10k file)
* `--memory <true | false>` whether to gather memory stats. This will severely
  skew any speed performance numbers. Defaults to false

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
    CMD mix benchmark -—profile huge cowboy bandit@main
    ```
3. Run like
    ```
    docker build -t build .
    docker run -d build
    docker logs -f <id>
    docker cp -a <id>:/apps .
    scp the output files
    ```
