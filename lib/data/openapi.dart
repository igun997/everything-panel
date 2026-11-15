import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One input of an API operation, taken from the OpenAPI document.
@immutable
class ApiField {
  const ApiField({
    required this.name,
    required this.schema,
    required this.required,
    required this.inQuery,
    this.description,
  });

  final String name;
  final Map<String, dynamic> schema;
  final bool required;

  /// Query parameter (GET) when true, otherwise a property of the JSON body (POST).
  final bool inQuery;
  final String? description;

  String? get type => schema['type'] as String?;
  List<String>? get enumValues => (schema['enum'] as List?)?.map((e) => '$e').toList();
  Object? get defaultValue => schema['default'];
}

enum ApiRisk { read, change, danger }

@immutable
class ApiOperation {
  const ApiOperation({
    required this.id,
    required this.method,
    required this.tag,
    required this.summary,
    required this.description,
    required this.fields,
  });

  final String id;

  /// `GET` or `POST`.
  final String method;
  final String tag;
  final String summary;
  final String description;
  final List<ApiField> fields;

  bool get isRead => method == 'GET';

  static final _dangerous = RegExp(r'^(destroy|delete|remove|kill|prune|reset|drop|uninstall|revoke|logout|disconnect)', caseSensitive: false);

  /// Reads run straight away. Anything that writes asks first; destructive names ask
  /// louder.
  ApiRisk get risk => isRead ? ApiRisk.read : (_dangerous.hasMatch(id) || id.contains('Prune') ? ApiRisk.danger : ApiRisk.change);
}

/// Every operation Easypanel documents, loaded from the bundled OpenAPI file, so the
/// whole API is reachable from the app and stays in step with the docs.
class ApiCatalog {
  ApiCatalog(this.version, this.operations) {
    for (final op in operations) {
      byTag.putIfAbsent(op.tag, () => []).add(op);
    }
    for (final list in byTag.values) {
      list.sort((a, b) => a.id.compareTo(b.id));
    }
  }

  final String version;
  final List<ApiOperation> operations;
  final Map<String, List<ApiOperation>> byTag = {};

  List<String> get tags => byTag.keys.toList()..sort();

  factory ApiCatalog.parse(String source) {
    final doc = jsonDecode(source) as Map<String, dynamic>;
    final ops = <ApiOperation>[];
    (doc['paths'] as Map<String, dynamic>).forEach((path, methods) {
      (methods as Map<String, dynamic>).forEach((method, raw) {
        final o = raw as Map<String, dynamic>;
        final fields = <ApiField>[];
        for (final p in (o['parameters'] as List? ?? const []).cast<Map<String, dynamic>>()) {
          fields.add(ApiField(
            name: p['name'] as String,
            schema: (p['schema'] as Map?)?.cast<String, dynamic>() ?? const {},
            required: p['required'] == true,
            inQuery: true,
            description: p['description'] as String?,
          ));
        }
        final body = o['requestBody'];
        if (body is Map) {
          final props = (body['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
          final req = ((body['required'] as List?) ?? const []).cast<String>().toSet();
          props.forEach((name, schema) {
            fields.add(ApiField(
              name: name,
              schema: (schema as Map).cast<String, dynamic>(),
              required: req.contains(name),
              inQuery: false,
              description: schema['description'] as String?,
            ));
          });
        }
        ops.add(ApiOperation(
          id: (o['operationId'] as String?) ?? path.substring(1),
          method: method.toUpperCase(),
          tag: ((o['tags'] as List?)?.firstOrNull as String?) ?? 'Other',
          summary: (o['summary'] as String?) ?? '',
          description: (o['description'] as String?) ?? '',
          fields: fields,
        ));
      });
    });
    return ApiCatalog((doc['info'] as Map?)?['version'] as String? ?? '', ops);
  }
}

/// Implemented by backends that can run arbitrary documented operations.
abstract class ApiExplorerBackend {
  ApiCatalog get catalog;

  /// Runs [op] with [input] (field name to typed value) and returns the decoded JSON.
  Future<Object?> invoke(ApiOperation op, Map<String, Object?> input);
}
