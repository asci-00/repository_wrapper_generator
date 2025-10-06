import 'package:analyzer/dart/element/element2.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:repository_isolate_wrapper/annotation.dart';
import 'package:source_gen/source_gen.dart';
import '../../src/model_visitor.dart';

class RepositoryWrapperGenerator
    extends GeneratorForAnnotation<RepositoryIsolateWrapper> {
  final _formatter = DartFormatter(
    pageWidth: 80,
    lineEnding: '\n',
    languageVersion: Version(3, 0, 0),
  );

  @override
  String generateForAnnotatedElement(
    Element2 element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    final visitor = ModelVisitor(annotation);
    element.accept2(visitor);

    final emitter = DartEmitter();
    final library = Library((b) {
      b.body.addAll([
        _buildWrapperClass(visitor),
        _buildMethodTypeEnum(visitor),
        ..._buildArgsClasses(visitor),
      ]);
    });

    return _formatter.format('${library.accept(emitter)}');
  }

  /// Wrapper class: ex) `ExecutionLogRepositoryWrapper`
  Class _buildWrapperClass(ModelVisitor visitor) {
    final info = visitor.classInfo;

    return Class((c) {
      c
        ..name = '${info.className}Wrapper'
        ..extend = refer(info.interfaceName)
        ..mixins.add(refer('RepositoryWrapperExecutor'))
        ..constructors.add(Constructor((ctor) => ctor.constant = true));

      c.methods.addAll(visitor.methodInfo.map(
        (method) => _buildWrapperMethod(method, info),
      ));
    });
  }

  Method _buildWrapperMethod(
    GeneratorMethodInfo method,
    GeneratorClassInfo classInfo,
  ) {
    return Method((m) {
      m
        ..annotations.add(refer('override'))
        ..name = method.name;

      if (method.isGetter) {
        m
          ..type = MethodType.getter
          ..returns = refer(method.returnType)
          ..body = Code(
            'return execute<${method.plainType}>(type: ${classInfo.methodTypeClass}.${method.name});',
          );
        return;
      }

      m
        ..modifier = MethodModifier.async
        ..returns = refer('Future<${method.plainType}>');

      _applyMethodParameters(m, method);

      final argsClass = method.arguments?.argumentClassName;
      final argsCall = _buildArgsConstructorCall(method);

      final execArgs = argsCall != null ? ', args: $argsClass($argsCall)' : '';

      m.body = Code(
        'return execute<${method.plainType}>(type: ${classInfo.methodTypeClass}.${method.name}$execArgs);',
      );
    });
  }

  void _applyMethodParameters(MethodBuilder m, GeneratorMethodInfo method) {
    if (method.arguments == null) return;

    for (final arg in method.arguments!.arguments) {
      final param = Parameter((p) {
        p.name = arg.name;
        p.type = refer(arg.type);
        p.named = arg.isNamed;
        p.required = arg.isRequired && arg.isNamed;
        p.defaultTo = arg.defaultValue != null ? Code(arg.defaultValue!) : null;
      });

      if (!arg.isNamed && arg.isRequired) {
        m.requiredParameters.add(param);
      } else {
        m.optionalParameters.add(param);
      }
    }
  }

  String? _buildArgsConstructorCall(GeneratorMethodInfo method) {
    if (method.arguments == null || method.arguments!.arguments.isEmpty) {
      return null;
    }
    return method.arguments!.arguments.map((a) => a.name).join(', ');
  }

  /// Enum implementing `RepositoryMethodType`
  Enum _buildMethodTypeEnum(ModelVisitor visitor) {
    final info = visitor.classInfo;

    return Enum((e) {
      e
        ..name = info.methodTypeClass
        ..implements.add(refer('RepositoryMethodType'));

      e.values.addAll(visitor.methodInfo.map(
        (method) => EnumValue((ev) => ev.name = method.name),
      ));

      e.methods.add(_buildRepositoryGetter(info));
      e.methods.add(_buildExecuteMethod(visitor, info));
    });
  }

  Method _buildRepositoryGetter(GeneratorClassInfo info) {
    return Method((m) {
      m
        ..name = 'repository'
        ..type = MethodType.getter
        ..annotations.add(refer('override'))
        ..returns = refer(info.interfaceName)
        ..body = Code(
          'return RepositoryFactory.getRepository<${info.interfaceName}>();',
        );
    });
  }

  Method _buildExecuteMethod(ModelVisitor visitor, GeneratorClassInfo info) {
    return Method((m) {
      m
        ..name = 'execute'
        ..annotations.add(refer('override'))
        ..modifier = MethodModifier.async
        ..returns = refer('Future<dynamic>')
        ..optionalParameters.add(
          Parameter((p) => p
            ..name = 'args'
            ..type = refer('IsolateExecuteArgs?')),
        );

      final buf = StringBuffer('switch (this) {');

      for (final method in visitor.methodInfo) {
        buf.writeln('case ${info.methodTypeClass}.${method.name}:');

        final args = method.arguments;
        final hasArgs = args != null && args.arguments.isNotEmpty;

        if (!hasArgs) {
          if (method.isGetter) {
            buf.writeln('return repository.${method.name};');
          } else {
            buf.writeln('return repository.${method.name}();');
          }
        } else {
          final argClass = args.argumentClassName;

          buf
            ..writeln('if (args is! $argClass) {')
            ..writeln(
                "  throw ArgumentError('args(\$args) is not type of ${method.name}');")
            ..writeln('}');

          final callArgs = args.arguments.map((a) {
            final access = 'args.${a.name}';
            return a.isNamed ? '${a.name}: $access' : access;
          }).join(', ');

          buf.writeln('return repository.${method.name}($callArgs);');
        }
      }

      buf.writeln('}');
      m.body = Code(buf.toString());
    });
  }

  /// Argument classes extending `IsolateExecuteArgs`
  List<Class> _buildArgsClasses(ModelVisitor visitor) {
    return visitor.methodInfo
        .where((m) => m.arguments != null)
        .map((m) => _buildArgsClass(m))
        .toList();
  }

  Class _buildArgsClass(GeneratorMethodInfo method) {
    final args = method.arguments!;
    return Class((c) {
      c
        ..name = args.argumentClassName
        ..extend = refer('IsolateExecuteArgs')
        ..constructors.add(Constructor((ctor) {
          ctor
            ..constant = true
            ..requiredParameters.addAll(args.arguments.map(
              (arg) => Parameter((p) => p
                ..toThis = true
                ..name = arg.name),
            ));
        }));

      for (final arg in args.arguments) {
        c.fields.add(Field((f) => f
          ..name = arg.name
          ..modifier = FieldModifier.final$
          ..type = refer(arg.type)));
      }
    });
  }
}
