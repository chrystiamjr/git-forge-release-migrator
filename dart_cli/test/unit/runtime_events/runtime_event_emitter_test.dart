import 'dart:convert';
import 'dart:io';

import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/runtime_events/console_runtime_event_sink.dart';
import 'package:gfrm_dart/src/runtime_events/in_memory_runtime_event_sink.dart';
import 'package:gfrm_dart/src/runtime_events/jsonl_runtime_event_sink.dart';
import 'package:gfrm_dart/src/runtime_events/reducer_runtime_event_sink.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_emitter.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_envelope.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_sink.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_type.dart';
import 'package:gfrm_dart/src/runtime_events/serial_runtime_event_publisher.dart';
import 'package:test/test.dart';

import '../../support/buffer_console_output.dart';
import '../../support/temp_dir.dart';

void main() {
  group('RuntimeEventEmitter', () {
    test('dispatches the same ordered stream to registered sinks deterministically', () {
      final Directory temp = createTempDir('gfrm-runtime-event-emitter-');
      final InMemoryRuntimeEventSink memorySink = InMemoryRuntimeEventSink();
      final List<String> reducerTrace = <String>[];
      final ReducerRuntimeEventSink<List<String>> reducerSink = ReducerRuntimeEventSink<List<String>>(
        id: 'reducer',
        initialState: <String>[],
        reducer: (List<String> currentState, RuntimeEventEnvelope envelope) {
          reducerTrace.add(envelope.eventType);
          return <String>[
            ...currentState,
            '${envelope.sequence}:${envelope.eventType}',
          ];
        },
      );
      final String jsonlPath = '${temp.path}/runtime-events.jsonl';
      final JsonlRuntimeEventSink jsonlSink = JsonlRuntimeEventSink(path: jsonlPath);
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );
      final ConsoleRuntimeEventSink consoleSink = ConsoleRuntimeEventSink(
        logger: logger,
        formatter: (RuntimeEventEnvelope envelope) => 'console:${envelope.sequence}:${envelope.eventType}',
      );
      final RuntimeEventEmitter emitter = RuntimeEventEmitter(
        publisher: SerialRuntimeEventPublisher(
          runId: 'run-emit',
          timestampFactory: () => '2026-04-09T15:00:00Z',
        ),
        sinks: <RuntimeEventSink>[
          memorySink,
          reducerSink,
          jsonlSink,
          consoleSink,
        ],
      );

      emitter.emit(
        eventType: RuntimeEventType.runStarted,
        payload: <String, dynamic>{
          'source_provider': 'gitlab',
          'target_provider': 'github',
          'mode': 'migrate',
        },
      );
      emitter.emit(
        eventType: RuntimeEventType.tagMigrated,
        payload: <String, dynamic>{
          'tag': 'v1.0.0',
          'status': 'created',
        },
      );

      expect(emitter.sinkIds, <String>['in-memory', 'reducer', 'jsonl', 'console']);
      expect(memorySink.events.map((RuntimeEventEnvelope event) => event.sequence), <int>[1, 2]);
      expect(memorySink.events.map((RuntimeEventEnvelope event) => event.eventType), <String>[
        'run_started',
        'tag_migrated',
      ]);
      expect(reducerTrace, <String>['run_started', 'tag_migrated']);
      expect(reducerSink.state, <String>['1:run_started', '2:tag_migrated']);
      expect(
        File(jsonlPath)
            .readAsLinesSync()
            .map((String line) => jsonDecode(line) as Map<String, dynamic>)
            .map((Map<String, dynamic> raw) => raw['event_type']),
        <String>['run_started', 'tag_migrated'],
      );
      expect(output.stdoutLines, <String>[
        '[INFO] console:1:run_started',
        '[INFO] console:2:tag_migrated',
      ]);
    });

    test('console sink uses default formatter when none is provided', () {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );
      final ConsoleRuntimeEventSink sink = ConsoleRuntimeEventSink(logger: logger);

      sink.consume(
        RuntimeEventEnvelope(
          runId: 'run-emit',
          sequence: 7,
          occurredAt: '2026-04-09T15:00:00Z',
          eventType: RuntimeEventType.runCompleted.value,
          payload: <String, dynamic>{'status': 'success'},
        ),
      );

      expect(output.stdoutLines.single, '[INFO] [runtime-event #7] run_completed');
    });
  });
}
