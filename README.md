# indi-server-simulator-chart

A Helm chart and container image for an [INDI](https://indilib.org) server that runs simulated astronomy devices: a mount, cameras, a focuser, a filter wheel, domes, a weather station and more. Simulators are chosen with Helm values, so you can add or remove one with `helm upgrade`.

It's meant for testing Flutter apps for iOS and Android built with [`indi`](https://pub.dev/packages/indi), the Dart INDI client ([source](https://github.com/torresj/dart-indi), [docs](https://dindi.torresj.es)), against real INDI drivers without any hardware. Clients connect to the server's public host on port 7624. This README uses `indi.example.com` as that host; use your own.

## Connecting from a Flutter app

```dart
import 'package:indi/indi.dart';

final client = IndiClient(host: 'indi.example.com', port: 7624);
await client.connect();

// Definitions arrive asynchronously after connecting.
final mount = client.device('Telescope Simulator');
```

- **Transport.** On Android and iOS, `IndiClient` opens a plain TCP socket (`TcpTransport`) on INDI's standard port, 7624.
  - **Android:** release builds need `<uses-permission android:name="android.permission.INTERNET"/>` in `android/app/src/main/AndroidManifest.xml`. Flutter only adds it to the debug and profile manifests.
  - **iOS:** App Transport Security only covers HTTP, so the socket needs no exception.
- **Flutter web** can't open TCP sockets. It needs a WebSocket bridge in front of indiserver, which this chart doesn't deploy.
- **The server is public, with no authentication and no TLS.** Everyone who connects shares the same devices: if two people slew the telescope, they move the same telescope.
- **Changing the simulators restarts the server.** Clients lose the connection for a few seconds. `IndiClient` reconnects on its own by default and emits `SessionResumed` once the properties are back.
- **Driver settings reset on every restart.** Drivers keep them in `~/.indi`, which is an `emptyDir`.
- **CCD images have no stars.** The image doesn't include the GSC star catalog that the CCD simulator uses to draw them.

## Simulators

Each value under `simulators` starts one INDI driver. The device names and interfaces below come from a live server running INDI 2.2.5, as reported by `indi`'s `IndiDevice.interfaces`.

| Value | Driver | INDI device | Interfaces | Default |
| --- | --- | --- | --- | --- |
| `telescope` | `indi_simulator_telescope` | Telescope Simulator | telescope, guider | on |
| `ccd` | `indi_simulator_ccd` | CCD Simulator | ccd, guider, filterWheel | on |
| `focuser` | `indi_simulator_focus` | Focuser Simulator | focuser | on |
| `filterWheel` | `indi_simulator_wheel` | Filter Simulator | filterWheel | on |
| `guider` | `indi_simulator_guide` | Guide Simulator | ccd, guider | off |
| `rotator` | `indi_simulator_rotator` | Rotator Simulator | rotator | off |
| `dome` | `indi_simulator_dome` | Dome Simulator | dome | off |
| `rollOffRoof` | `indi_rolloff_dome` | RollOff Simulator | dome | off |
| `gps` | `indi_simulator_gps` | GPS Simulator | gps | off |
| `weather` | `indi_simulator_weather` | Weather Simulator | weather | off |
| `lightPanel` | `indi_simulator_lightpanel` | Light Panel Simulator | lightBox, auxiliary | off |
| `dustCover` | `indi_simulator_dustcover` | Dust Cover Simulator | dustCap, auxiliary | off |
| `io` | `indi_simulator_io` | Simulator IO | auxiliary, output, input | off |
| `receiver` | `indi_simulator_receiver` | Receiver Simulator | spectrograph | off |
| `sqm` | `indi_simulator_sqm` | SQM Simulator | none | off |
| `alignmentCorrection` | `indi_simulator_pac` | Alignment Correction Simulator | auxiliary, polarAlignmentCorrection | off |

`examples/` has two presets:
- [`imaging.yaml`](examples/imaging.yaml): mount, main and guide cameras, focuser, filter wheel and rotator.
- [`observatory.yaml`](examples/observatory.yaml): the imaging rig plus dome, weather, GPS, dust cover and light panel.

## Install and change simulators

You deploy with Helm by hand. CI only builds and publishes the image and the chart (see [Releasing](#releasing)). The image is in a private registry, so the namespace needs an image pull secret named `regcred` before the first install.

```sh
kubectl create namespace indi
kubectl create secret docker-registry regcred -n indi \
  --docker-server=<REGISTRY_URL> --docker-username=<REGISTRY_USER> --docker-password=<REGISTRY_PASSWORD>

helm repo add torresj <CHARTS_URL> --username <CHARTS_USER> --password <CHARTS_PASSWORD>
helm repo update

helm upgrade --install indi-server-simulator torresj/indi-server-simulator -n indi \
  --set publicEndpoint.host=indi.example.com
helm test indi-server-simulator -n indi   # checks that the drivers answer
```

To change the simulators:

```sh
# Add the dome and the weather station, keeping the rest of the current values
helm upgrade indi-server-simulator torresj/indi-server-simulator -n indi --reuse-values \
  --set simulators.dome=true --set simulators.weather=true

# Switch to a preset: the chart defaults plus the file
helm upgrade indi-server-simulator torresj/indi-server-simulator -n indi -f examples/observatory.yaml

# Show the values the release runs with
helm get values indi-server-simulator -n indi
```

- **Values are checked before anything changes.**
  - An unknown simulator, such as `--set simulators.dom=true`, fails against `values.schema.json`.
  - A string where a boolean is expected (`--set-string`) fails too.
  - A configuration with no drivers fails to render.
- **Moving to a newer chart version:** use `--reset-then-reuse-values` instead of `--reuse-values`. It takes the new chart's defaults and then applies your previous values.
- **From a checkout:** use `helm/indi-server-simulator` in place of `torresj/indi-server-simulator`. The image tag defaults to the chart's `appVersion`, so that version must already be released.

## Values

| Value | Default | Description |
| --- | --- | --- |
| `simulators.<name>` | see [Simulators](#simulators) | Starts the simulator when `true` |
| `extraDrivers` | `[]` | More drivers to start after the simulators: another executable in the image, or a device on another INDI server as `"device@host:port"` |
| `server.verbose` | `1` | indiserver logging: `0` quiet, `1` key events (`-v`), `2` message content (`-vv`), `3` complete XML (`-vvv`) |
| `server.maxQueueMB` | `128` | Drops a client that falls this many MB behind (`-m`). CCD images are sent as BLOBs, so slow mobile links need room |
| `server.maxRestarts` | `10` | How many times a crashed driver is restarted (`-r`) |
| `server.extraArgs` | `[]` | Other indiserver flags, such as `["-d", "64"]` to drop streaming BLOBs for slow clients |
| `service.type` / `service.port` | `ClusterIP` / `7624` | The in-cluster Service, `indi-server-simulator.indi.svc:7624` |
| `publicEndpoint.host` / `.port` | `indi.example.com` / `7624` | The public address shown in the install notes; set it to your hostname. Exposing the port is a separate step (see below) |
| `image.repository` / `.tag` / `.pullPolicy` | `registry.torresj.es/indi-server-simulator` / chart `appVersion` / `IfNotPresent` | The image |
| `imagePullSecrets` | `regcred` | Pull secret for the private registry |
| `resources` | requests `50m`/`64Mi`, limits `500m`/`512Mi` | The CCD simulator needs the most, while it renders images |
| `podSecurityContext` / `securityContext` | non-root uid 10001, read-only root filesystem, no capabilities | Writable `emptyDir` volumes are mounted at `/home/indi` and `/tmp` |
| `podAnnotations`, `nodeSelector`, `tolerations`, `affinity` | empty | Standard pod scheduling settings |

There's always exactly one replica, and updates use the `Recreate` strategy. The simulated devices live in the indiserver process, so a second replica would show each client a different sky.

## Public access on port 7624

A Kubernetes `Ingress` only routes HTTP, and INDI is XML over raw TCP. Instead, ingress-nginx proxies the TCP port itself, on the external IP of its LoadBalancer Service; point your hostname's DNS record at that IP. The mapping belongs to the ingress-nginx release, not to this chart, and [`k8s/ingress-nginx-tcp.yaml`](k8s/ingress-nginx-tcp.yaml) holds it. Apply it once, passing the chart version that's already installed (`helm list -n ingress-nginx` shows it):

```sh
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx \
  --version <installed chart version> --reuse-values -f k8s/ingress-nginx-tcp.yaml
```

- **What it does.** The ingress-nginx chart creates the `ingress-nginx-tcp` ConfigMap and passes it to the controller with `--tcp-services-configmap`. It also adds port 7624 to the controller's LoadBalancer Service.
- **Version.** `--version` keeps the installed controller version, so the command changes nothing else.
- **Restart.** The controller pod is replaced, so the HTTP sites on the cluster can blip for a few seconds.

Then check it from outside the cluster:

```sh
nc -vz indi.example.com 7624
cd ../dart-indi && dart run example/main.dart indi.example.com 7624   # lists devices, slews, takes an image
```

If the connection times out, check that the server's firewall allows port 7624. To use another public port or namespace, change `k8s/ingress-nginx-tcp.yaml` and `publicEndpoint`.

## The image

[`Dockerfile`](Dockerfile) installs `indi-bin`, which holds `indiserver` and the simulators, from the official [INDI PPA](https://launchpad.net/~mutlaqja/+archive/ubuntu/ppa) on `ubuntu:26.04`. It runs as uid 10001 with `HOME=/home/indi`.

- **Why 26.04.** The PPA builds INDI 2.x only for recent Ubuntu releases. On 24.04 it has no build, and apt silently falls back to Ubuntu's own INDI 1.9.9, so the build fails if it ends up with INDI 1.x.
- **INDI version.** The PPA keeps only its latest build, so each image gets the INDI version that is current when it's built. 2.2.5 was current in October 2026. To see the version in an image:

  ```sh
  docker run --rm --entrypoint dpkg-query registry.torresj.es/indi-server-simulator:<version> -W indi-bin
  ```

- **Running it locally.** `docker run --rm -p 7624:7624 registry.torresj.es/indi-server-simulator:<version>` starts the four default simulators. Arguments after the image replace them, for example `-v indi_simulator_telescope indi_simulator_dome`.

### Adding a simulator

When a new INDI release adds a simulator, add its key in five places:
1. The driver map in `helm/indi-server-simulator/templates/_helpers.tpl`.
2. `values.yaml`.
3. `values.schema.json`.
4. `ci/all-simulators-values.yaml`.
5. The table above.

CI checks that every key renders a driver and that every driver starts in the image.

## Releasing

1. Set `version` and `appVersion` in `helm/indi-server-simulator/Chart.yaml` to the same new version.
2. Merge to `main`, then push a `vX.Y.Z` tag that matches.
3. CI checks the version, builds and tests the image, and pushes `registry.torresj.es/indi-server-simulator:X.Y.Z` and the chart to ChartMuseum.
4. Run `helm repo update`, then `helm upgrade indi-server-simulator torresj/indi-server-simulator -n indi --reset-then-reuse-values`.

To pick up a newer INDI from the PPA, cut a new release. An existing tag is never rebuilt.

Every push and pull request runs [`.github/workflows/ci.yml`](.github/workflows/ci.yml):
- It lints the chart with every values file and checks that bad values are rejected.
- It builds the image and starts it with every simulator, using the chart's arguments and a read-only filesystem.
- It fails unless every driver defines a device. The device names appear in the run summary.

### GitHub Actions secrets

| Secret | Purpose |
| --- | --- |
| `REGISTRY_URL`, `REGISTRY_USER`, `REGISTRY_PASSWORD` | Docker registry |
| `CHARTS_URL`, `CHARTS_USER`, `CHARTS_PASSWORD` | ChartMuseum |

Only `v*` tags use them. CI has no cluster access.

## License

This repository is licensed under the GPL-3.0 (see [LICENSE](LICENSE)). The [INDI Library](https://github.com/indilib/indi) that the image installs is licensed under the LGPL.
