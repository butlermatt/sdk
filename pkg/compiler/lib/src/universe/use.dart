// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This library defined `uses`. A `use` is a single impact of the world, for
/// instance an invocation of a top level function or a call to the `foo()`
/// method on an unknown class.
library dart2js.universe.use;

import '../closure.dart' show
  BoxFieldElement;
import '../common.dart';
import '../dart_types.dart';
import '../elements/elements.dart';
import '../world.dart' show
    ClassWorld;
import '../util/util.dart' show
    Hashing;

import 'call_structure.dart' show
    CallStructure;
import 'selector.dart' show
    Selector;
import 'universe.dart' show
    ReceiverConstraint;


enum DynamicUseKind {
  INVOKE,
  GET,
  SET,
}

/// The use of a dynamic property. [selector] defined the name and kind of the
/// property and [mask] defines the known constraint for the object on which
/// the property is accessed.
class DynamicUse {
  final Selector selector;
  final ReceiverConstraint mask;

  DynamicUse(this.selector, this.mask);

  bool appliesUnnamed(Element element, ClassWorld world) {
    return selector.appliesUnnamed(element, world) &&
        (mask == null || mask.canHit(element, selector, world));
  }

  DynamicUseKind get kind {
    if (selector.isGetter) {
      return DynamicUseKind.GET;
    } else if (selector.isSetter) {
      return DynamicUseKind.SET;
    } else {
      return DynamicUseKind.INVOKE;
    }
  }

  int get hashCode => selector.hashCode * 13 + mask.hashCode * 17;

  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is! DynamicUse) return false;
    return selector == other.selector && mask == other.mask;
  }

  String toString() => '$selector,$mask';
}

enum StaticUseKind {
  GENERAL,
  STATIC_TEAR_OFF,
  SUPER_TEAR_OFF,
  SUPER_FIELD_SET,
  FIELD_GET,
  FIELD_SET,
  CLOSURE,
}

/// Statically known use of an [Element].
// TODO(johnniwinther): Create backend-specific implementations with better
// invariants.
class StaticUse {
  final Element element;
  final StaticUseKind kind;
  final int hashCode;

  StaticUse._(Element element, StaticUseKind kind)
      : this.element = element,
        this.kind = kind,
        this.hashCode = Hashing.objectHash(element, Hashing.objectHash(kind)) {
    assert(invariant(element, element.isDeclaration,
        message: "Static use element $element must be "
                 "the declaration element."));
  }

  /// Invocation of a static or top-level [element] with the given
  /// [callStructure].
  factory StaticUse.staticInvoke(MethodElement element,
                                 CallStructure callStructure) {
    // TODO(johnniwinther): Use the [callStructure].
    assert(invariant(element, element.isStatic || element.isTopLevel,
        message: "Static invoke element $element must be a top-level "
                 "or static method."));
    return new StaticUse._(element, StaticUseKind.GENERAL);
  }

  /// Closurization of a static or top-level function [element].
  factory StaticUse.staticTearOff(MethodElement element) {
    assert(invariant(element, element.isStatic || element.isTopLevel,
        message: "Static tear-off element $element must be a top-level "
                 "or static method."));
    return new StaticUse._(element, StaticUseKind.STATIC_TEAR_OFF);
  }

  /// Read access of a static or top-level field or getter [element].
  factory StaticUse.staticGet(MemberElement element) {
    assert(invariant(element, element.isStatic || element.isTopLevel,
        message: "Static get element $element must be a top-level "
                 "or static method."));
    assert(invariant(element, element.isField || element.isGetter,
        message: "Static get element $element must be a field or a getter."));
    return new StaticUse._(element, StaticUseKind.GENERAL);
  }

  /// Write access of a static or top-level field or setter [element].
  factory StaticUse.staticSet(MemberElement element) {
    assert(invariant(element, element.isStatic || element.isTopLevel,
        message: "Static set element $element must be a top-level "
                 "or static method."));
    assert(invariant(element, element.isField || element.isSetter,
        message: "Static set element $element must be a field or a setter."));
    return new StaticUse._(element, StaticUseKind.GENERAL);
  }

  /// Invocation of the lazy initializer for a static or top-level field
  /// [element].
  factory StaticUse.staticInit(FieldElement element) {
    assert(invariant(element, element.isStatic || element.isTopLevel,
        message: "Static init element $element must be a top-level "
                 "or static method."));
    assert(invariant(element, element.isField,
        message: "Static init element $element must be a field."));
    return new StaticUse._(element, StaticUseKind.GENERAL);
  }

  /// Invocation of a super method [element] with the given [callStructure].
  factory StaticUse.superInvoke(MethodElement element,
                                CallStructure callStructure) {
    // TODO(johnniwinther): Use the [callStructure].
    assert(invariant(element, element.isInstanceMember,
        message: "Super invoke element $element must be an instance method."));
    return new StaticUse._(element, StaticUseKind.GENERAL);
  }

  /// Read access of a super field or getter [element].
  factory StaticUse.superGet(MemberElement element) {
    assert(invariant(element, element.isInstanceMember,
        message: "Super get element $element must be an instance method."));
    assert(invariant(element, element.isField || element.isGetter,
        message: "Super get element $element must be a field or a getter."));
    return new StaticUse._(element, StaticUseKind.GENERAL);
  }

  /// Write access of a super field [element].
  factory StaticUse.superFieldSet(FieldElement element) {
    assert(invariant(element, element.isInstanceMember,
        message: "Super set element $element must be an instance method."));
    assert(invariant(element, element.isField,
        message: "Super set element $element must be a field."));
    return new StaticUse._(element, StaticUseKind.SUPER_FIELD_SET);
  }

  /// Write access of a super setter [element].
  factory StaticUse.superSetterSet(SetterElement element) {
    assert(invariant(element, element.isInstanceMember,
        message: "Super set element $element must be an instance method."));
    assert(invariant(element, element.isSetter,
        message: "Super set element $element must be a setter."));
    return new StaticUse._(element, StaticUseKind.GENERAL);
  }

  /// Closurization of a super method [element].
  factory StaticUse.superTearOff(MethodElement element) {
    assert(invariant(element, element.isInstanceMember && element.isFunction,
        message: "Super invoke element $element must be an instance method."));
    return new StaticUse._(element, StaticUseKind.SUPER_TEAR_OFF);
  }

  /// Invocation of a constructor [element] through a this or super
  /// constructor call with the given [callStructure].
  factory StaticUse.superConstructorInvoke(Element element,
                                           CallStructure callStructure) {
    // TODO(johnniwinther): Use the [callStructure].
    assert(invariant(element,
        element.isGenerativeConstructor,
        message: "Constructor invoke element $element must be a "
                 "generative constructor."));
    return new StaticUse._(element, StaticUseKind.GENERAL);
  }

  /// Invocation of a constructor (body) [element] through a this or super
  /// constructor call with the given [callStructure].
  factory StaticUse.constructorBodyInvoke(ConstructorBodyElement element,
                                          CallStructure callStructure) {
    // TODO(johnniwinther): Use the [callStructure].
    return new StaticUse._(element, StaticUseKind.GENERAL);
  }

  /// Constructor invocation of [element] with the given [callStructure].
  factory StaticUse.constructorInvoke(ConstructorElement element,
                                      CallStructure callStructure) {
    // TODO(johnniwinther): Use the [callStructure].
    return new StaticUse._(element, StaticUseKind.GENERAL);
  }

  /// Constructor redirection to [element].
  factory StaticUse.constructorRedirect(ConstructorElement element) {
    return new StaticUse._(element, StaticUseKind.GENERAL);
  }

  /// Initialization of an instance field [element].
  factory StaticUse.fieldInit(FieldElement element) {
    assert(invariant(element, element.isInstanceMember,
        message: "Field init element $element must be an instance field."));
    return new StaticUse._(element, StaticUseKind.GENERAL);
  }

  /// Read access of an instance field or boxed field [element].
  factory StaticUse.fieldGet(Element element) {
    assert(invariant(element,
        element.isInstanceMember || element is BoxFieldElement,
        message: "Field init element $element must be an instance "
                 "or boxed field."));
    return new StaticUse._(element, StaticUseKind.FIELD_GET);
  }

  /// Write access of an instance field or boxed field [element].
  factory StaticUse.fieldSet(Element element) {
    assert(invariant(element,
        element.isInstanceMember || element is BoxFieldElement,
        message: "Field init element $element must be an instance "
                 "or boxed field."));
    return new StaticUse._(element, StaticUseKind.FIELD_SET);
  }

  /// Read of a local function [element].
  factory StaticUse.closure(LocalFunctionElement element) {
    return new StaticUse._(element, StaticUseKind.CLOSURE);
  }

  /// Unknown use of [element].
  @deprecated
  factory StaticUse.foreignUse(Element element) {
    return new StaticUse._(element, StaticUseKind.GENERAL);
  }

  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is! StaticUse) return false;
    return element == other.element &&
           kind == other.kind;
  }

  String toString() => 'StaticUse($element,$kind)';
}

enum TypeUseKind {
  IS_CHECK,
  AS_CAST,
  CHECKED_MODE_CHECK,
  CATCH_TYPE,
  TYPE_LITERAL,
  INSTANTIATION,
}

/// Use of a [DartType].
class TypeUse {
  final DartType type;
  final TypeUseKind kind;
  final int hashCode;

  TypeUse._(DartType type, TypeUseKind kind)
      : this.type = type,
        this.kind = kind,
        this.hashCode = Hashing.objectHash(type, Hashing.objectHash(kind));

  /// [type] used in an is check, like `e is T` or `e is! T`.
  factory TypeUse.isCheck(DartType type) {
    return new TypeUse._(type, TypeUseKind.IS_CHECK);
  }

  /// [type] used in an as cast, like `e as T`.
  factory TypeUse.asCast(DartType type) {
    return new TypeUse._(type, TypeUseKind.AS_CAST);
  }

  /// [type] used as a type annotation, like `T foo;`.
  factory TypeUse.checkedModeCheck(DartType type) {
    return new TypeUse._(type, TypeUseKind.CHECKED_MODE_CHECK);
  }

  /// [type] used in a on type catch clause, like `try {} on T catch (e) {}`.
  factory TypeUse.catchType(DartType type) {
    return new TypeUse._(type, TypeUseKind.CATCH_TYPE);
  }

  /// [type] used as a type literal, like `foo() => T;`.
  factory TypeUse.typeLiteral(DartType type) {
    return new TypeUse._(type, TypeUseKind.TYPE_LITERAL);
  }

  /// [type] used in an instantiation, like `new T();`.
  factory TypeUse.instantiation(InterfaceType type) {
    return new TypeUse._(type, TypeUseKind.INSTANTIATION);
  }

  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is! TypeUse) return false;
    return type == other.type &&
           kind == other.kind;
  }

  String toString() => 'TypeUse($type,$kind)';
}