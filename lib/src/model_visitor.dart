import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/visitor2.dart';
import 'package:source_gen/source_gen.dart';

class GeneratorClassInfo {
  GeneratorClassInfo({
    required this.interfaceName,
    required this.repositoryType,
  }) : assert(
          interfaceName[0] == 'I',
          'The interface name must start with \'I\'',
        );

  final String interfaceName;
  final String repositoryType;

  String get methodTypeClass => '_\$${className}MethodType';

  String get className => interfaceName.substring(1);
}

class GeneratorMethodArgumentsInfo {
  const GeneratorMethodArgumentsInfo({
    required this.methodName,
    required this.arguments,
  }) : assert(methodName.length < 2,
            'The method name must be at least 2 characters.');

  final String methodName;
  final List<GeneratorMethodArgumentInfo> arguments;

  String get argumentClassName =>
      '_\$${methodName[0].toUpperCase() + methodName.substring(1)}Args';
}

class GeneratorMethodArgumentInfo {
  const GeneratorMethodArgumentInfo({
    required this.type,
    required this.name,
    required this.isNamed,
    required this.isRequired,
    required this.defaultValue,
  });

  final String type;
  final String name;
  final bool isNamed;
  final bool isRequired;
  final String? defaultValue;
}

class GeneratorMethodInfo {
  const GeneratorMethodInfo({
    required this.name,
    required this.returnType,
    required this.arguments,
    required this.isGetter,
    required this.methodDeclare,
  });

  final String name;
  final String returnType;
  final GeneratorMethodArgumentsInfo? arguments;
  final String methodDeclare;

  final bool isGetter;

  String get plainType => returnType.replaceFirstMapped(
      RegExp(r'^Future<([a-zA-Z<>(){},? \n]+)>$'),
      (match) => match.group(1) ?? 'void');

  String get kebabCaseName => name.toUpperCase() + name.substring(1);
}

class ModelVisitor extends SimpleElementVisitor2<void> {
  ModelVisitor(this.annotation);

  late GeneratorClassInfo classInfo;
  final List<GeneratorMethodInfo> methodInfo = [];
  final ConstantReader annotation;

  @override
  void visitClassElement(ClassElement2 element) {
    classInfo = GeneratorClassInfo(
      interfaceName: element.name3 ?? '',
      repositoryType:
          annotation.read('type').objectValue.variable2?.displayName ??
              'UnknownType',
    );

    for (final constructor in element.constructors2) {
      constructor.accept2(this);
    }
    for (final field in element.fields2) {
      field.accept2(this);
    }
    for (final method in element.methods2) {
      method.accept2(this);
    }
  }

  @override
  void visitFieldElement(FieldElement2 element) {
    methodInfo.add(
      GeneratorMethodInfo(
        name: element.name3 ?? '',
        methodDeclare: element.displayString2(),
        returnType: element.type.getDisplayString(),
        arguments: null,
        isGetter: true,
      ),
    );
  }

  @override
  void visitMethodElement(MethodElement2 element) {
    final arguments = element.formalParameters.isNotEmpty
        ? GeneratorMethodArgumentsInfo(
            methodName: element.name3 ?? '',
            arguments: element.formalParameters.map((param) {
              return GeneratorMethodArgumentInfo(
                name: param.name3 ?? '',
                type: param.type.getDisplayString(),
                isNamed: param.isNamed,
                isRequired: param.isRequiredNamed || param.isRequiredPositional,
                defaultValue: param.defaultValueCode,
              );
            }).toList(),
          )
        : null;

    methodInfo.add(
      GeneratorMethodInfo(
        name: element.name3 ?? '',
        methodDeclare: element.displayName,
        returnType: element.returnType.getDisplayString(),
        arguments: arguments,
        isGetter: false,
      ),
    );
  }
}
