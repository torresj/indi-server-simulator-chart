{{/*
Expand the name of the chart.
*/}}
{{- define "indi-server-simulator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "indi-server-simulator.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "indi-server-simulator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "indi-server-simulator.labels" -}}
helm.sh/chart: {{ include "indi-server-simulator.chart" . }}
{{ include "indi-server-simulator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "indi-server-simulator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "indi-server-simulator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
The driver behind each key of .Values.simulators: every simulator that
indi-bin installs (INDI 2.2.5).
To add a simulator, add its key here, in values.yaml and in
values.schema.json.
*/}}
{{- define "indi-server-simulator.simulatorDrivers" -}}
alignmentCorrection: indi_simulator_pac
ccd: indi_simulator_ccd
dome: indi_simulator_dome
dustCover: indi_simulator_dustcover
filterWheel: indi_simulator_wheel
focuser: indi_simulator_focus
gps: indi_simulator_gps
guider: indi_simulator_guide
io: indi_simulator_io
lightPanel: indi_simulator_lightpanel
receiver: indi_simulator_receiver
rollOffRoof: indi_rolloff_dome
rotator: indi_simulator_rotator
sqm: indi_simulator_sqm
telescope: indi_simulator_telescope
weather: indi_simulator_weather
{{- end }}

{{/*
The drivers indiserver starts, as a JSON list: the enabled simulators, then
.Values.extraDrivers. indiserver exits without drivers, so an empty list
fails the render.
*/}}
{{- define "indi-server-simulator.drivers" -}}
{{- $drivers := list }}
{{- range $key, $driver := fromYaml (include "indi-server-simulator.simulatorDrivers" .) }}
{{- if index $.Values.simulators $key }}
{{- $drivers = append $drivers $driver }}
{{- end }}
{{- end }}
{{- $drivers = concat $drivers .Values.extraDrivers }}
{{- if not $drivers }}
{{- fail "No drivers to start: enable at least one simulator (for example --set simulators.telescope=true) or add an extraDrivers entry." }}
{{- end }}
{{- toJson $drivers }}
{{- end }}

{{/*
The indiserver command line, as a YAML list.
*/}}
{{- define "indi-server-simulator.args" -}}
{{- $server := .Values.server }}
{{- $args := list }}
{{- if gt (int $server.verbose) 0 }}
{{- $args = append $args (printf "-%s" (repeat (int $server.verbose) "v")) }}
{{- end }}
{{- $args = concat $args (list "-m" (toString (int $server.maxQueueMB)) "-r" (toString (int $server.maxRestarts))) }}
{{- range $server.extraArgs }}
{{- $args = append $args (toString .) }}
{{- end }}
{{- $args = concat $args (fromJsonArray (include "indi-server-simulator.drivers" .)) }}
{{- toYaml $args }}
{{- end }}
