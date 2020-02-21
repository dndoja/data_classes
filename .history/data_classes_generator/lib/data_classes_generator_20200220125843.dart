import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:build/src/builder/build_step.dart';
import 'package:source_gen/source_gen.dart';
import 'package:data_classes/data_classes.dart';

const modelClassSuffix = 'Model';

Builder generateDataClass(BuilderOptions options) =>
    SharedPartBuilder([DataClassGenerator()], 'data_classes');

class CodeGenError extends Error {
  CodeGenError(this.message);
  final String message;
  String toString() => message;
}

class DataClassGenerator extends GeneratorForAnnotation<GenerateDataClass> {
  @override
  generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep _,
  ) {
    if (element is! ClassElement) {
      throw CodeGenError(
          'You can only annotate classes with @GenerateDataClass(), but '
          '"${element.name}" isn\'t a class.');
    }
    if (!element.name.endsWith(modelClassSuffix)) {
      throw CodeGenError(
          'The names of classes annotated with @GenerateDataClass() should '
          'end with "Model", for example ${element.name}Model. The '
          'immutable class (in that case, ${element.name}) will then get '
          'automatically generated for you by running "pub run build_runner '
          'build" (or "flutter pub run build_runner build" if you\'re using '
          'Flutter).');
    }

    final originalClass = element as ClassElement;
    final name = originalClass.name
        .substring(0, originalClass.name.length - modelClassSuffix.length);

    // When import prefixes (`import '...' as '...';`) are used in the mutable
    // class's file, then in the generated file, we need to use the right
    // prefix in front of the type in the immutable class too. So here, we map
    // the module identifiers to their import prefixes.
    Map<String, String> qualifiedImports = {
      for (final import in originalClass.library.imports)
        if (import.prefix != null)
          import.importedLibrary.identifier: import.prefix.name,
    };

    // Collect all the fields and getters from the original class.
    final fields = <FieldElement>{};
    final getters = <FieldElement>{};

    for (final field in originalClass.fields) {
      // print(
      //     '$field ${field.initializer} ${field.initializer} ${field.computeConstantValue()}');
      // if (field.isFinal && !field.isSynthetic) {
      //   throw CodeGenError(
      //       'Mutable classes shouldn\'t have final fields, but the class '
      //       '$name$modelClassSuffix has the final field ${field.name}.');
      // } else
      if (field.setter == null) {
        assert(field.getter != null);
        getters.add(field);
        // } else if (field.getter == null) {
        //   assert(field.setter != null);
        //   throw CodeGenError(
        //       'Mutable classes shouldn\'t have setter-only fields, but the '
        //       'class $name$modelClassSuffix has the field ${field.name}, which only has a '
        //       'setter.');
      } else {
        // TODO: Create a flag to disallow dynamic types
        // if (field.type.toString().contains('dynamic')) {
        //   throw CodeGenError(
        //     'Dynamic types are not allowed.\n'
        //     'Fix:\n'
        //     '  class $name$modelClassSuffix {\n'
        //     '    ...\n'
        //     '    <SpecificType> ${field.name};'
        //     '    ...\n'
        //     '  }',
        //   );
        // }
        fields.add(field);
      }
    }

    // Check whether we should generate a `copyWith` method. Also ensure that
    // there are no nullable fields.
    final builtValueSerializer = originalClass.metadata
        .firstWhere((annotation) =>
            annotation.element?.enclosingElement?.name == 'GenerateDataClass')
        .constantValue
        .getField('builtValueSerializer')
        .toBoolValue();
    final generateCopyWith = originalClass.metadata
        .firstWhere((annotation) =>
            annotation.element?.enclosingElement?.name == 'GenerateDataClass')
        .constantValue
        .getField('copyWith')
        .toBoolValue();
    final immutable = originalClass.metadata
        .firstWhere((annotation) =>
            annotation.element?.enclosingElement?.name == 'GenerateDataClass')
        .constantValue
        .getField('immutable')
        .toBoolValue();
    final serialize = originalClass.metadata
        .firstWhere((annotation) =>
            annotation.element?.enclosingElement?.name == 'GenerateDataClass')
        .constantValue
        .getField('serialize')
        .toBoolValue();
    if (generateCopyWith && fields.any(_isNullable)) {
      final exampleField = fields.firstWhere(_isNullable).name;
      // throw CodeGenError(
      //     'You tried to generate a copyWith method for the "$name" class (which '
      //     'gets generated based on the "$name$modelClassSuffix" class). Unfortunately, '
      //     'you can only generate this method if all the fields are '
      //     'non-nullable, but for example, the "$exampleField" field is marked '
      //     'with @nullable. If you really want a copyWith method, you should '
      //     'consider removing that annotation.\n'
      //     'Why does this rule exist? Let\'s say, we would allow the copyWith '
      //     'method to get generated. If you would call it, it would have no '
      //     'way of knowing whether you just didn\'t pass in a "$exampleField" as '
      //     'a parameter or you intentionally tried to set it to null, because '
      //     'in both cases, the function parameter would be null. That makes '
      //     'the code vulnerable to subtle bugs when passing variables to the '
      //     'copyWith method. '
      //     'For more information about this, see the following GitHub issue: '
      //     'https://github.com/marcelgarus/data_classes/issues/3');

      // TODO: Show the warning below only when the respective flag is set
      // print(
      //   'You try to generate a copyWith method for the "$name" class (which '
      //   'gets generated based on the "$name$modelClassSuffix" class). However, the'
      //   ' "$exampleField" field is marked with @nullable, you should '
      //   'consider removing that annotation.\n'
      //   'Let\'s say, we would allow the copyWith method to get generated. '
      //   'If you would call it, it would have no '
      //   'way of knowing whether you just didn\'t pass in a "$exampleField" as '
      //   'a parameter or you intentionally tried to set it to null, because '
      //   'in both cases, the function parameter would be null. That makes '
      //   'the code vulnerable to subtle bugs when passing variables to the '
      //   'copyWith method. '
      //   'For more information about this, see the following GitHub issue: '
      //   'https://github.com/marcelgarus/data_classes/issues/3',
      // );
    }

    // Users can annotate fields that hold an enum value with
    // `@GenerateValueGetters()` to generate value getters.
    // Here, we prepare a map from the getter name to its code content.
    final valueGetters = <String, String>{};
    for (final field in fields) {
      final annotation = field.metadata
          .firstWhere(
              (annotation) =>
                  annotation.element?.enclosingElement?.name ==
                  'GenerateValueGetters',
              orElse: () => null)
          ?.computeConstantValue();
      if (annotation == null) continue;

      final usePrefix = annotation.getField('usePrefix').toBoolValue();
      final generateNegations =
          annotation.getField('generateNegations').toBoolValue();

      final enumClass = field.type.element as ClassElement;
      if (enumClass?.isEnum == false) {
        throw CodeGenError(
            'You annotated the $name$modelClassSuffix\'s ${field.name} with '
            '@GenerateValueGetters(), but that\'s of '
            '${enumClass == null ? 'an unknown type' : 'the type ${enumClass.name}'}, '
            'which is not an enum. @GenerateValueGetters() should only be '
            'used on fields of an enum type.');
      }

      final prefix = 'is${usePrefix ? _capitalize(field.name) : ''}';
      final enumValues = enumClass.fields
          .where((field) => !['values', 'index'].contains(field.name));

      for (final value in enumValues) {
        for (final negate in generateNegations ? [false, true] : [false]) {
          final getter =
              '$prefix${negate ? 'Not' : ''}${_capitalize(value.name)}';
          final content = 'this.${field.name} ${negate ? '!=' : '=='} '
              '${_qualifiedType(value.type, qualifiedImports)}.${value.name}';

          if (valueGetters.containsKey(getter)) {
            throw CodeGenError(
                'A conflict occurred while generating value getters. The two '
                'conflicting value getters of the $name$modelClassSuffix class are:\n'
                '- $getter, which tests if ${valueGetters[getter]}\n'
                '- $getter, which tests if $content');
          }

          valueGetters[getter] = content;
        }
      }
    }

    final String nameUncapitalized =
        name.substring(0, 1).toLowerCase() + name.substring(1);

    final Iterable<String> asserts = fields
        .where((field) => !_isNullable(field))
        .map((field) => 'assert(${field.name} != null)');

    // Actually generate the class.
    final buffer = StringBuffer();
    buffer.writeAll([
      '// ignore_for_file: implicit_dynamic_parameter, argument_type_not_assignable',
      '// ignore_for_file: must_be_immutable, prefer_asserts_with_message',
      '// ignore_for_file: always_put_required_named_parameters_first',
      '// ignore_for_file: sort_constructors_first, lines_longer_than_80_chars',
      '// ignore_for_file: prefer_expression_function_bodies',

      // Start of the class.
      originalClass.documentationComment ??
          '/// This class is the pendant of the [$name$modelClassSuffix] class.',
      if (immutable)
        '@immutable',
      'class $name extends $name$modelClassSuffix {',
      '$name$modelClassSuffix _model;\n',

      // The field members.
      for (final field in fields) ...[
        if (field.documentationComment != null) field.documentationComment,
        '@override',
        // TODO: Resolve issue with the lack of analyzer error when setting overridden final fields
        if (immutable || field.isFinal)
          _fieldToTypeAndName(field, qualifiedImports),
        // if (field.initializer != null) ' = ${field.initializer}',
        ';',
      ],

      // The value getters.
      '\n  // Value getters.',
      for (final getter in valueGetters.entries)
        'bool get ${getter.key} => ${getter.value};',

      // The default constructor.
      '/// Default constructor that creates a new [$name]',
      '/// with the given attributes',
      'factory $name({',
      for (final field in fields) ...[
        if (_isRequired(field)) '@required ',
        '${field.type} ${field.name},'
      ],
      '}) {',
      'final model = $name$modelClassSuffix();',
      'return $name._(',
      for (final field in fields)
        '${field.name}: ${field.name} ?? model.${field.name},',
      ');',
      '}\n',

      '$name._({',
      for (final field in fields) 'this.${field.name},',
      '})',
      if (asserts.isNotEmpty)
        ': ',
      asserts.join(','),
      ';\n',

      // Converters (fromMutable and toMutable).
      '/// Creates a [$name] from a [$name$modelClassSuffix].',
      '$name.fromMutable($name$modelClassSuffix mutable) : ',
      fields.map((field) => '${field.name} = mutable.${field.name}').join(','),
      ';\n',
      '/// Turns [$name] into a [$name$modelClassSuffix].',
      '$name$modelClassSuffix toMutable() => $name$modelClassSuffix()',
      fields.map((field) => '..${field.name} = ${field.name}').join(),
      ';\n',

      // Deep equality stuff (== and hashCode).
      /// https://stackoverflow.com/questions/10404516/how-can-i-compare-lists-for-equality-in-dart
      '/// Checks if this [$name] is equal to the other one.',
      '@override',
      'bool operator ==(Object other) {',
      'bool Function(dynamic e1, dynamic e2) eq = const DeepCollectionEquality().equals;\n',
      'return identical(this, other) || other is $name$modelClassSuffix &&',

      fields
          .map(
            (field) =>
                // field.type.displayName.startsWith('List')
                // ? 'eq(${field.name}, other.${field.name})'
                // : '${field.name} == other.${field.name}')
                'eq(${field.name}, other.${field.name})',
          )
          .join(' &&\n'),
      ';\n}\n',
      '@override',
      'int get hashCode => hashList([',
      fields.map((field) => field.name).join(', '),
      ']);\n',

      /// copy
      // TODO: Let change function be optional
      '/// Copies this [$name] with some changed attributes.',
      '$name copy(void Function($name$modelClassSuffix source) changeAttributes) {',
      'assert(changeAttributes != null,',
      '\'You called $name.copy, \'',
      '\'but did not provide a function for changing the attributes.\\n\'',
      '\'If you just want an unchanged copy: You do not need one, just use \'',
      '\'the original.\',',
      ');',
      'final mutable = this.toMutable();',
      'changeAttributes(mutable);\n',
      'return $name.fromMutable(mutable);',
      '}\n',

      // copyWith
      if (generateCopyWith) ...[
        '/// Copies this [$name] with some changed attributes.',
        '$name copyWith({',
        for (final field in fields)
          '${_fieldToTypeAndName(field, qualifiedImports)},',
        '}) => $name(',
        for (final field in fields)
          '${field.name}: ${field.name} ?? this.${field.name},',
        ');',
      ],

      // toString converter.
      '/// Converts this [$name] into a [String].',
      '@override',
      "String toString() => \'$name(\\n'",
      for (final field in fields) "'  ${field.name}: \$${field.name}\\n'",
      "')';\n",

      if (serialize) ...[
        // fromJson
        'static $name fromJson(Map<dynamic, dynamic> json) =>',
        '$name.fromMutable(_\$$name${modelClassSuffix}FromJson(json));\n',

        // toJson
        'Map<dynamic, dynamic> toJson() =>',
        '_\$$name${modelClassSuffix}ToJson(this.toMutable());\n',

        if (builtValueSerializer)
          'static Serializer<$name> get serializer => _\$${nameUncapitalized}Serializer;'
      ],

      // End of the class.
      '}',

      if (serialize && builtValueSerializer) ...[
        'Serializer<$name> _\$${nameUncapitalized}Serializer = new _\$${name}Serializer();\n',
        'class _\$${name}Serializer implements StructuredSerializer<$name> {',
        '  @override',
        '  final Iterable<Type> types = const [$name];',
        '  @override',
        '  final String wireName = \'$name\';\n',
        '  @override',
        '  Iterable<Object> serialize(Serializers serializers, $name object,',
        '      {FullType specifiedType = FullType.unspecified}) {',
        '    final json = _\$$name${modelClassSuffix}ToJson(object);',
        '    final List<Object> result = [];',
        '    json.forEach((k, v) => result.addAll([k, v]));\n',
        '    return result;',
        '  }\n',
        '  @override',
        '  $name deserialize(Serializers serializers, Iterable<Object> serialized,',
        '      {FullType specifiedType = FullType.unspecified}) {',
        '    final Map<dynamic, dynamic> json = {};',
        '    final serializedAsList = serialized.toList();',
        '    serializedAsList.asMap().forEach((i, key) {',
        '      if (i.isEven) json[key] = serializedAsList[i + 1];',
        '    });\n',
        '    return $name.fromMutable(_\$$name${modelClassSuffix}FromJson(json),);',
        '  }\n',
        '}',
      ]
    ].expand((line) => [line, '\n']));

    return buffer.toString();
  }

  /// Whether the [field] is nullable.
  bool _isNullable(FieldElement field) {
    assert(field != null);

    return field.metadata
        .any((annotation) => annotation.element.name == nullable);
  }

  /// Whether the [field] is nullable.
  bool _isRequired(FieldElement field) {
    assert(field != null);

    return !_isNullable(field) && field.initializer == null;
  }

  /// Capitalizes the first letter of a string.
  String _capitalize(String string) {
    assert(string.isNotEmpty);
    return string[0].toUpperCase() + string.substring(1);
  }

  /// Turns the [field] into type and the field name, separated by a space.
  String _fieldToTypeAndName(
    FieldElement field,
    Map<String, String> qualifiedImports,
  ) {
    assert(field != null);
    assert(qualifiedImports != null);

    return '${_qualifiedType(field.type, qualifiedImports)} ${field.name}';
  }

  String _fieldGetter(
    FieldElement field,
    Map<String, String> qualifiedImports,
  ) {
    assert(field != null);
    assert(qualifiedImports != null);

    return '@override\n'
        '${_qualifiedType(field.type, qualifiedImports)} get ${field.name} => '
        '_model.${field.name}';
  }

  String _fieldSetter(
    FieldElement field,
    Map<String, String> qualifiedImports,
  ) {
    assert(field != null);
    assert(qualifiedImports != null);

    return '${_qualifiedType(field.type, qualifiedImports)} ${field.name}';
  }

  /// Turns the [type] into a type with prefix.
  String _qualifiedType(DartType type, Map<String, String> qualifiedImports) {
    final typeLibrary = type.element.library;
    final prefixOrNull = qualifiedImports[typeLibrary?.identifier];
    final prefix = (prefixOrNull != null) ? '$prefixOrNull.' : '';

    return '$prefix$type';
  }
}
