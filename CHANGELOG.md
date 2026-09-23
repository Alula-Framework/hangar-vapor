# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-09-23

### Changed

- **The organization is now Alula-Framework**, after Flight was renamed
  Alula. Hangar is required at 0.9.2, the release that points at
  swift-changeset's new URL. GitHub redirects the old URLs, and the API is
  unchanged.

## [0.2.0] - 2026-09-19

No API change. The surface is still three things: a pool on `Application`, a
per-request `Repo` that logs under the request's ID, and graceful shutdown.

### Changed

- **Requires hangar 0.9.0.** The floor had said 0.3.0 while hangar shipped
  0.5.0, 0.5.1 and 0.6.0, and nothing here had been built against any of them:
  this package's CI only fires on pushes to this repository, and the last was
  2026-08-31 — the day hangar tagged 0.4.0.

- **hangar's CI builds this package on every commit.** That is the durable
  half, and the reason the drift above cannot recur. Wiring it took four
  attempts, each a wrong assumption about the runner rather than about the
  code: a concurrency group that is the caller's and so cancelled this job
  before it started, a bare checkout that clones the caller, a path dependency
  whose directory name becomes its package identity, and a `nc` that is not in
  the Swift image.

- **The integration gate is a real check.** It tested whether a variable was
  empty in a step that set it to a literal on the line above, so it could
  never fire. It opens the socket now.

- **macOS builds and is required.** The job was advisory on the grounds that
  swift-configuration could not compile on Darwin. That was an SDK question:
  on the macos-26 image it builds, with the deployment target untouched.

## [0.1.0] - 2026-08-24

First release. Predates this changelog.
