import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fyrpods/main.dart';
import 'package:fyrpods/models/pod_models.dart';
import 'package:fyrpods/services/container_engine.dart';
import 'package:fyrpods/state/pods_controller.dart';

void main() {
  group('fyrPods ContainerEngine & PodsController Unit Tests', () {
    test('parses Podman and Docker ps/images JSON formats accurately', () {
      const podmanContainersJson = '''
[
  {
    "Id": "8f91e2a3b4c5d6e7f8a9b0c1d2e3f4a5",
    "Names": ["fyr-api-gateway"],
    "Image": "ghcr.io/fyrde/gateway:1.27-alpine",
    "State": "running",
    "Status": "Up 3 hours (healthy)",
    "Pod": "pod-123",
    "PodName": "fyr-cloud-stack",
    "Ports": [
      {"host_ip": "0.0.0.0", "host_port": 8080, "container_port": 80, "protocol": "tcp"}
    ]
  }
]
''';
      final parsed = ContainerEngine.parseContainersJson(podmanContainersJson);
      expect(parsed.length, 1);
      expect(parsed.first.name, 'fyr-api-gateway');
      expect(parsed.first.state, ContainerStateStatus.running);
      expect(parsed.first.podName, 'fyr-cloud-stack');
      expect(parsed.first.ports.first.formatted, '0.0.0.0:8080->80/tcp');

      const podmanImagesJson = '''
[
  {
    "Id": "sha256:9f8b7a6c5d4e3f2a1b0c9d8e7f6a5b4c",
    "Names": ["ollama/ollama:latest"],
    "Size": 3586129920,
    "Containers": 1
  }
]
''';
      final images = ContainerEngine.parseImagesJson(podmanImagesJson);
      expect(images.length, 1);
      expect(images.first.repository, 'ollama/ollama');
      expect(images.first.tag, 'latest');
      expect(images.first.inUse, isTrue);
    });

    test('manages container lifecycle, Kube YAML deployment, images, and exec',
        () async {
      final ctrl = PodsController(allowLiveCli: false, enableTicker: false);
      expect(ctrl.containers.length, 7);
      expect(ctrl.runningContainersCount, 5);

      // Stop and start a container
      ctrl.stopContainer('c-gateway-nginx');
      expect(ctrl.runningContainersCount, 4);
      ctrl.startContainer('c-gateway-nginx');
      expect(ctrl.runningContainersCount, 5);

      // Pause and unpause a container
      ctrl.pauseContainer('c-redis-cache');
      expect(
        ctrl.containers.firstWhere((c) => c.id == 'c-redis-cache').state,
        ContainerStateStatus.paused,
      );
      ctrl.pauseContainer('c-redis-cache');
      expect(
        ctrl.containers.firstWhere((c) => c.id == 'c-redis-cache').state,
        ContainerStateStatus.running,
      );

      // Create & remove a new container
      final created = ctrl.createContainer(
        name: 'fyr-test-worker',
        image: 'alpine:3.20',
        ports: const [PortMapping(hostPort: 9100, containerPort: 9100)],
      );
      expect(ctrl.containers.length, 8);
      expect(created.state, ContainerStateStatus.running);

      // Generate Kubernetes & Compose YAML
      final kubeYaml = ContainerEngine.generateKubeYaml(created);
      expect(kubeYaml, contains('apiVersion: v1'));
      expect(kubeYaml, contains('kind: Pod'));
      expect(kubeYaml, contains('image: alpine:3.20'));

      final composeYaml = ContainerEngine.generateComposeYaml([created]);
      expect(composeYaml, contains('services:'));
      expect(composeYaml, contains('fyr-test-worker:'));

      // Exec command inside container
      final execOut = await ctrl.execCommand(created.id, 'uname -a');
      expect(execOut, contains('Linux'));

      // Deploy Kube YAML
      final pod = ctrl.deployKubeYaml('''
apiVersion: v1
kind: Pod
metadata:
  name: fyr-analytics-pod
spec:
  containers:
    - name: analytics
      image: prom/prometheus:v3.0.0
      ports:
        - containerPort: 9090
          hostPort: 9095
''');
      expect(pod.name, 'fyr-analytics-pod');
      expect(ctrl.pods.first.name, 'fyr-analytics-pod');

      // Pull image, create volume & network
      ctrl.pullImage('redis:7.4-alpine');
      expect(ctrl.images.length, 7);
      ctrl.createVolume(name: 'fyr-test-vol');
      expect(ctrl.volumes.length, 5);
      ctrl.createNetwork(name: 'fyr-test-net');
      expect(ctrl.networks.length, 4);

      ctrl.removeContainer(created.id);
      ctrl.dispose();
    });
  });

  group('fyrPods UI Widget Smoke Test', () {
    testWidgets(
        'renders TopBar, SidebarNav, ContainersView, Inspector, and switches views',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 880);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final ctrl = PodsController(allowLiveCli: false, enableTicker: false);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: ctrl,
          child: const FyrPodsApp(),
        ),
      );
      await tester.pump();

      expect(find.text('fyrPods'), findsOneWidget);
      expect(find.text('Containers'), findsOneWidget);
      expect(find.text('Pods & Stacks'), findsOneWidget);
      expect(find.text('fyr-llm-runner'), findsWidgets);
      expect(find.text('fyr-gateway-nginx'), findsOneWidget);

      // Switch to Pods & Stacks view
      await tester.tap(find.text('Pods & Stacks'));
      await tester.pump();
      expect(find.text('fyr-cloud-stack'), findsOneWidget);
      expect(find.text('fyr-ai-inference'), findsOneWidget);

      // Switch to Images view
      await tester.tap(find.text('Images'));
      await tester.pump();
      expect(find.text('ollama/ollama'), findsOneWidget);

      // Switch to Volumes view
      await tester.tap(find.text('Volumes'));
      await tester.pump();
      expect(find.text('fyr-ollama-models'), findsOneWidget);

      // Switch to Networks view
      await tester.tap(find.text('Networks'));
      await tester.pump();
      expect(find.text('fyr-mesh-br0'), findsOneWidget);

      ctrl.dispose();
    });
  });
}
