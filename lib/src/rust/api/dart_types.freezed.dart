// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'dart_types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LayerConfig {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LayerConfig);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LayerConfig()';
}


}

/// @nodoc
class $LayerConfigCopyWith<$Res>  {
$LayerConfigCopyWith(LayerConfig _, $Res Function(LayerConfig) __);
}


/// Adds pattern-matching-related methods to [LayerConfig].
extension LayerConfigPatterns on LayerConfig {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LayerConfig_Osm value)?  osm,TResult Function( LayerConfig_RasterTiles value)?  rasterTiles,TResult Function( LayerConfig_VectorTiles value)?  vectorTiles,TResult Function( LayerConfig_PolygonLayer value)?  polygonLayer,TResult Function( LayerConfig_PointLayer value)?  pointLayer,TResult Function( LayerConfig_WidgetLayer value)?  widgetLayer,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LayerConfig_Osm() when osm != null:
return osm(_that);case LayerConfig_RasterTiles() when rasterTiles != null:
return rasterTiles(_that);case LayerConfig_VectorTiles() when vectorTiles != null:
return vectorTiles(_that);case LayerConfig_PolygonLayer() when polygonLayer != null:
return polygonLayer(_that);case LayerConfig_PointLayer() when pointLayer != null:
return pointLayer(_that);case LayerConfig_WidgetLayer() when widgetLayer != null:
return widgetLayer(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LayerConfig_Osm value)  osm,required TResult Function( LayerConfig_RasterTiles value)  rasterTiles,required TResult Function( LayerConfig_VectorTiles value)  vectorTiles,required TResult Function( LayerConfig_PolygonLayer value)  polygonLayer,required TResult Function( LayerConfig_PointLayer value)  pointLayer,required TResult Function( LayerConfig_WidgetLayer value)  widgetLayer,}){
final _that = this;
switch (_that) {
case LayerConfig_Osm():
return osm(_that);case LayerConfig_RasterTiles():
return rasterTiles(_that);case LayerConfig_VectorTiles():
return vectorTiles(_that);case LayerConfig_PolygonLayer():
return polygonLayer(_that);case LayerConfig_PointLayer():
return pointLayer(_that);case LayerConfig_WidgetLayer():
return widgetLayer(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LayerConfig_Osm value)?  osm,TResult? Function( LayerConfig_RasterTiles value)?  rasterTiles,TResult? Function( LayerConfig_VectorTiles value)?  vectorTiles,TResult? Function( LayerConfig_PolygonLayer value)?  polygonLayer,TResult? Function( LayerConfig_PointLayer value)?  pointLayer,TResult? Function( LayerConfig_WidgetLayer value)?  widgetLayer,}){
final _that = this;
switch (_that) {
case LayerConfig_Osm() when osm != null:
return osm(_that);case LayerConfig_RasterTiles() when rasterTiles != null:
return rasterTiles(_that);case LayerConfig_VectorTiles() when vectorTiles != null:
return vectorTiles(_that);case LayerConfig_PolygonLayer() when polygonLayer != null:
return polygonLayer(_that);case LayerConfig_PointLayer() when pointLayer != null:
return pointLayer(_that);case LayerConfig_WidgetLayer() when widgetLayer != null:
return widgetLayer(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  osm,TResult Function( String urlTemplate,  String? attribution)?  rasterTiles,TResult Function( String urlTemplate,  String styleJson,  String? attribution)?  vectorTiles,TResult Function( List<Polygon> features)?  polygonLayer,TResult Function( List<Point> features)?  pointLayer,TResult Function()?  widgetLayer,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LayerConfig_Osm() when osm != null:
return osm();case LayerConfig_RasterTiles() when rasterTiles != null:
return rasterTiles(_that.urlTemplate,_that.attribution);case LayerConfig_VectorTiles() when vectorTiles != null:
return vectorTiles(_that.urlTemplate,_that.styleJson,_that.attribution);case LayerConfig_PolygonLayer() when polygonLayer != null:
return polygonLayer(_that.features);case LayerConfig_PointLayer() when pointLayer != null:
return pointLayer(_that.features);case LayerConfig_WidgetLayer() when widgetLayer != null:
return widgetLayer();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  osm,required TResult Function( String urlTemplate,  String? attribution)  rasterTiles,required TResult Function( String urlTemplate,  String styleJson,  String? attribution)  vectorTiles,required TResult Function( List<Polygon> features)  polygonLayer,required TResult Function( List<Point> features)  pointLayer,required TResult Function()  widgetLayer,}) {final _that = this;
switch (_that) {
case LayerConfig_Osm():
return osm();case LayerConfig_RasterTiles():
return rasterTiles(_that.urlTemplate,_that.attribution);case LayerConfig_VectorTiles():
return vectorTiles(_that.urlTemplate,_that.styleJson,_that.attribution);case LayerConfig_PolygonLayer():
return polygonLayer(_that.features);case LayerConfig_PointLayer():
return pointLayer(_that.features);case LayerConfig_WidgetLayer():
return widgetLayer();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  osm,TResult? Function( String urlTemplate,  String? attribution)?  rasterTiles,TResult? Function( String urlTemplate,  String styleJson,  String? attribution)?  vectorTiles,TResult? Function( List<Polygon> features)?  polygonLayer,TResult? Function( List<Point> features)?  pointLayer,TResult? Function()?  widgetLayer,}) {final _that = this;
switch (_that) {
case LayerConfig_Osm() when osm != null:
return osm();case LayerConfig_RasterTiles() when rasterTiles != null:
return rasterTiles(_that.urlTemplate,_that.attribution);case LayerConfig_VectorTiles() when vectorTiles != null:
return vectorTiles(_that.urlTemplate,_that.styleJson,_that.attribution);case LayerConfig_PolygonLayer() when polygonLayer != null:
return polygonLayer(_that.features);case LayerConfig_PointLayer() when pointLayer != null:
return pointLayer(_that.features);case LayerConfig_WidgetLayer() when widgetLayer != null:
return widgetLayer();case _:
  return null;

}
}

}

/// @nodoc


class LayerConfig_Osm extends LayerConfig {
  const LayerConfig_Osm(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LayerConfig_Osm);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LayerConfig.osm()';
}


}




/// @nodoc


class LayerConfig_RasterTiles extends LayerConfig {
  const LayerConfig_RasterTiles({required this.urlTemplate, this.attribution}): super._();
  

 final  String urlTemplate;
 final  String? attribution;

/// Create a copy of LayerConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LayerConfig_RasterTilesCopyWith<LayerConfig_RasterTiles> get copyWith => _$LayerConfig_RasterTilesCopyWithImpl<LayerConfig_RasterTiles>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LayerConfig_RasterTiles&&(identical(other.urlTemplate, urlTemplate) || other.urlTemplate == urlTemplate)&&(identical(other.attribution, attribution) || other.attribution == attribution));
}


@override
int get hashCode {
    return Object.hash(runtimeType,urlTemplate,attribution);
}

@override
String toString() {
    return 'LayerConfig.rasterTiles(urlTemplate: $urlTemplate, attribution: $attribution)';
}


}

/// @nodoc
abstract mixin class $LayerConfig_RasterTilesCopyWith<$Res> implements $LayerConfigCopyWith<$Res> {
  factory $LayerConfig_RasterTilesCopyWith(LayerConfig_RasterTiles value, $Res Function(LayerConfig_RasterTiles) _then) = _$LayerConfig_RasterTilesCopyWithImpl;
@useResult
$Res call({
 String urlTemplate, String? attribution
});




}
/// @nodoc
class _$LayerConfig_RasterTilesCopyWithImpl<$Res>
    implements $LayerConfig_RasterTilesCopyWith<$Res> {
  _$LayerConfig_RasterTilesCopyWithImpl(this._self, this._then);

  final LayerConfig_RasterTiles _self;
  final $Res Function(LayerConfig_RasterTiles) _then;

/// Create a copy of LayerConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? urlTemplate = null,Object? attribution = freezed,}) {
  return _then(LayerConfig_RasterTiles(
urlTemplate: null == urlTemplate ? _self.urlTemplate : urlTemplate // ignore: cast_nullable_to_non_nullable
as String,attribution: freezed == attribution ? _self.attribution : attribution // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class LayerConfig_VectorTiles extends LayerConfig {
  const LayerConfig_VectorTiles({required this.urlTemplate, required this.styleJson, this.attribution}): super._();
  

 final  String urlTemplate;
 final  String styleJson;
 final  String? attribution;

/// Create a copy of LayerConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LayerConfig_VectorTilesCopyWith<LayerConfig_VectorTiles> get copyWith => _$LayerConfig_VectorTilesCopyWithImpl<LayerConfig_VectorTiles>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LayerConfig_VectorTiles&&(identical(other.urlTemplate, urlTemplate) || other.urlTemplate == urlTemplate)&&(identical(other.styleJson, styleJson) || other.styleJson == styleJson)&&(identical(other.attribution, attribution) || other.attribution == attribution));
}


@override
int get hashCode {
    return Object.hash(runtimeType,urlTemplate,styleJson,attribution);
}

@override
String toString() {
    return 'LayerConfig.vectorTiles(urlTemplate: $urlTemplate, styleJson: $styleJson, attribution: $attribution)';
}


}

/// @nodoc
abstract mixin class $LayerConfig_VectorTilesCopyWith<$Res> implements $LayerConfigCopyWith<$Res> {
  factory $LayerConfig_VectorTilesCopyWith(LayerConfig_VectorTiles value, $Res Function(LayerConfig_VectorTiles) _then) = _$LayerConfig_VectorTilesCopyWithImpl;
@useResult
$Res call({
 String urlTemplate, String styleJson, String? attribution
});




}
/// @nodoc
class _$LayerConfig_VectorTilesCopyWithImpl<$Res>
    implements $LayerConfig_VectorTilesCopyWith<$Res> {
  _$LayerConfig_VectorTilesCopyWithImpl(this._self, this._then);

  final LayerConfig_VectorTiles _self;
  final $Res Function(LayerConfig_VectorTiles) _then;

/// Create a copy of LayerConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? urlTemplate = null,Object? styleJson = null,Object? attribution = freezed,}) {
  return _then(LayerConfig_VectorTiles(
urlTemplate: null == urlTemplate ? _self.urlTemplate : urlTemplate // ignore: cast_nullable_to_non_nullable
as String,styleJson: null == styleJson ? _self.styleJson : styleJson // ignore: cast_nullable_to_non_nullable
as String,attribution: freezed == attribution ? _self.attribution : attribution // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class LayerConfig_PolygonLayer extends LayerConfig {
  const LayerConfig_PolygonLayer({required  List<Polygon> features}): _features = features,super._();
  

/// Stores the Polygon features to be rendered
 final  List<Polygon> _features;
/// Stores the Polygon features to be rendered
 List<Polygon> get features {
  if (_features is EqualUnmodifiableListView) return _features;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_features);
}


/// Create a copy of LayerConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LayerConfig_PolygonLayerCopyWith<LayerConfig_PolygonLayer> get copyWith => _$LayerConfig_PolygonLayerCopyWithImpl<LayerConfig_PolygonLayer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LayerConfig_PolygonLayer&&const DeepCollectionEquality().equals(other.features, _features));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_features));
}

@override
String toString() {
    return 'LayerConfig.polygonLayer(features: $features)';
}


}

/// @nodoc
abstract mixin class $LayerConfig_PolygonLayerCopyWith<$Res> implements $LayerConfigCopyWith<$Res> {
  factory $LayerConfig_PolygonLayerCopyWith(LayerConfig_PolygonLayer value, $Res Function(LayerConfig_PolygonLayer) _then) = _$LayerConfig_PolygonLayerCopyWithImpl;
@useResult
$Res call({
 List<Polygon> features
});




}
/// @nodoc
class _$LayerConfig_PolygonLayerCopyWithImpl<$Res>
    implements $LayerConfig_PolygonLayerCopyWith<$Res> {
  _$LayerConfig_PolygonLayerCopyWithImpl(this._self, this._then);

  final LayerConfig_PolygonLayer _self;
  final $Res Function(LayerConfig_PolygonLayer) _then;

/// Create a copy of LayerConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? features = null,}) {
  return _then(LayerConfig_PolygonLayer(
features: null == features ? _self._features : features // ignore: cast_nullable_to_non_nullable
as List<Polygon>,
  ));
}


}

/// @nodoc


class LayerConfig_PointLayer extends LayerConfig {
  const LayerConfig_PointLayer({required  List<Point> features}): _features = features,super._();
  

/// Stores the Point features to be rendered
 final  List<Point> _features;
/// Stores the Point features to be rendered
 List<Point> get features {
  if (_features is EqualUnmodifiableListView) return _features;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_features);
}


/// Create a copy of LayerConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LayerConfig_PointLayerCopyWith<LayerConfig_PointLayer> get copyWith => _$LayerConfig_PointLayerCopyWithImpl<LayerConfig_PointLayer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LayerConfig_PointLayer&&const DeepCollectionEquality().equals(other.features, _features));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_features));
}

@override
String toString() {
    return 'LayerConfig.pointLayer(features: $features)';
}


}

/// @nodoc
abstract mixin class $LayerConfig_PointLayerCopyWith<$Res> implements $LayerConfigCopyWith<$Res> {
  factory $LayerConfig_PointLayerCopyWith(LayerConfig_PointLayer value, $Res Function(LayerConfig_PointLayer) _then) = _$LayerConfig_PointLayerCopyWithImpl;
@useResult
$Res call({
 List<Point> features
});




}
/// @nodoc
class _$LayerConfig_PointLayerCopyWithImpl<$Res>
    implements $LayerConfig_PointLayerCopyWith<$Res> {
  _$LayerConfig_PointLayerCopyWithImpl(this._self, this._then);

  final LayerConfig_PointLayer _self;
  final $Res Function(LayerConfig_PointLayer) _then;

/// Create a copy of LayerConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? features = null,}) {
  return _then(LayerConfig_PointLayer(
features: null == features ? _self._features : features // ignore: cast_nullable_to_non_nullable
as List<Point>,
  ));
}


}

/// @nodoc


class LayerConfig_WidgetLayer extends LayerConfig {
  const LayerConfig_WidgetLayer(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LayerConfig_WidgetLayer);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LayerConfig.widgetLayer()';
}


}




/// @nodoc
mixin _$UserEvent {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as UserEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserEvent&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as UserEvent;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as UserEvent;
  return 'UserEvent(field0: ${_this.field0})';
}


}

/// @nodoc
class $UserEventCopyWith<$Res>  {
$UserEventCopyWith(UserEvent _, $Res Function(UserEvent) __);
}


/// Adds pattern-matching-related methods to [UserEvent].
extension UserEventPatterns on UserEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UserEvent_ButtonPressed value)?  buttonPressed,TResult Function( UserEvent_ButtonReleased value)?  buttonReleased,TResult Function( UserEvent_Click value)?  click,TResult Function( UserEvent_DoubleClick value)?  doubleClick,TResult Function( UserEvent_PointerMoved value)?  pointerMoved,TResult Function( UserEvent_DragStarted value)?  dragStarted,TResult Function( UserEvent_Drag value)?  drag,TResult Function( UserEvent_DragEnded value)?  dragEnded,TResult Function( UserEvent_Scroll value)?  scroll,TResult Function( UserEvent_Zoom value)?  zoom,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UserEvent_ButtonPressed() when buttonPressed != null:
return buttonPressed(_that);case UserEvent_ButtonReleased() when buttonReleased != null:
return buttonReleased(_that);case UserEvent_Click() when click != null:
return click(_that);case UserEvent_DoubleClick() when doubleClick != null:
return doubleClick(_that);case UserEvent_PointerMoved() when pointerMoved != null:
return pointerMoved(_that);case UserEvent_DragStarted() when dragStarted != null:
return dragStarted(_that);case UserEvent_Drag() when drag != null:
return drag(_that);case UserEvent_DragEnded() when dragEnded != null:
return dragEnded(_that);case UserEvent_Scroll() when scroll != null:
return scroll(_that);case UserEvent_Zoom() when zoom != null:
return zoom(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UserEvent_ButtonPressed value)  buttonPressed,required TResult Function( UserEvent_ButtonReleased value)  buttonReleased,required TResult Function( UserEvent_Click value)  click,required TResult Function( UserEvent_DoubleClick value)  doubleClick,required TResult Function( UserEvent_PointerMoved value)  pointerMoved,required TResult Function( UserEvent_DragStarted value)  dragStarted,required TResult Function( UserEvent_Drag value)  drag,required TResult Function( UserEvent_DragEnded value)  dragEnded,required TResult Function( UserEvent_Scroll value)  scroll,required TResult Function( UserEvent_Zoom value)  zoom,}){
final _that = this;
switch (_that) {
case UserEvent_ButtonPressed():
return buttonPressed(_that);case UserEvent_ButtonReleased():
return buttonReleased(_that);case UserEvent_Click():
return click(_that);case UserEvent_DoubleClick():
return doubleClick(_that);case UserEvent_PointerMoved():
return pointerMoved(_that);case UserEvent_DragStarted():
return dragStarted(_that);case UserEvent_Drag():
return drag(_that);case UserEvent_DragEnded():
return dragEnded(_that);case UserEvent_Scroll():
return scroll(_that);case UserEvent_Zoom():
return zoom(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UserEvent_ButtonPressed value)?  buttonPressed,TResult? Function( UserEvent_ButtonReleased value)?  buttonReleased,TResult? Function( UserEvent_Click value)?  click,TResult? Function( UserEvent_DoubleClick value)?  doubleClick,TResult? Function( UserEvent_PointerMoved value)?  pointerMoved,TResult? Function( UserEvent_DragStarted value)?  dragStarted,TResult? Function( UserEvent_Drag value)?  drag,TResult? Function( UserEvent_DragEnded value)?  dragEnded,TResult? Function( UserEvent_Scroll value)?  scroll,TResult? Function( UserEvent_Zoom value)?  zoom,}){
final _that = this;
switch (_that) {
case UserEvent_ButtonPressed() when buttonPressed != null:
return buttonPressed(_that);case UserEvent_ButtonReleased() when buttonReleased != null:
return buttonReleased(_that);case UserEvent_Click() when click != null:
return click(_that);case UserEvent_DoubleClick() when doubleClick != null:
return doubleClick(_that);case UserEvent_PointerMoved() when pointerMoved != null:
return pointerMoved(_that);case UserEvent_DragStarted() when dragStarted != null:
return dragStarted(_that);case UserEvent_Drag() when drag != null:
return drag(_that);case UserEvent_DragEnded() when dragEnded != null:
return dragEnded(_that);case UserEvent_Scroll() when scroll != null:
return scroll(_that);case UserEvent_Zoom() when zoom != null:
return zoom(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( MouseButton field0,  MouseEvent field1)?  buttonPressed,TResult Function( MouseButton field0,  MouseEvent field1)?  buttonReleased,TResult Function( MouseButton field0,  MouseEvent field1)?  click,TResult Function( MouseButton field0,  MouseEvent field1)?  doubleClick,TResult Function( MouseEvent field0)?  pointerMoved,TResult Function( MouseButton field0,  MouseEvent field1)?  dragStarted,TResult Function( MouseButton field0,  Vector2 field1,  MouseEvent field2)?  drag,TResult Function( MouseButton field0,  MouseEvent field1)?  dragEnded,TResult Function( double field0,  MouseEvent field1)?  scroll,TResult Function( double field0,  Point2 field1)?  zoom,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UserEvent_ButtonPressed() when buttonPressed != null:
return buttonPressed(_that.field0,_that.field1);case UserEvent_ButtonReleased() when buttonReleased != null:
return buttonReleased(_that.field0,_that.field1);case UserEvent_Click() when click != null:
return click(_that.field0,_that.field1);case UserEvent_DoubleClick() when doubleClick != null:
return doubleClick(_that.field0,_that.field1);case UserEvent_PointerMoved() when pointerMoved != null:
return pointerMoved(_that.field0);case UserEvent_DragStarted() when dragStarted != null:
return dragStarted(_that.field0,_that.field1);case UserEvent_Drag() when drag != null:
return drag(_that.field0,_that.field1,_that.field2);case UserEvent_DragEnded() when dragEnded != null:
return dragEnded(_that.field0,_that.field1);case UserEvent_Scroll() when scroll != null:
return scroll(_that.field0,_that.field1);case UserEvent_Zoom() when zoom != null:
return zoom(_that.field0,_that.field1);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( MouseButton field0,  MouseEvent field1)  buttonPressed,required TResult Function( MouseButton field0,  MouseEvent field1)  buttonReleased,required TResult Function( MouseButton field0,  MouseEvent field1)  click,required TResult Function( MouseButton field0,  MouseEvent field1)  doubleClick,required TResult Function( MouseEvent field0)  pointerMoved,required TResult Function( MouseButton field0,  MouseEvent field1)  dragStarted,required TResult Function( MouseButton field0,  Vector2 field1,  MouseEvent field2)  drag,required TResult Function( MouseButton field0,  MouseEvent field1)  dragEnded,required TResult Function( double field0,  MouseEvent field1)  scroll,required TResult Function( double field0,  Point2 field1)  zoom,}) {final _that = this;
switch (_that) {
case UserEvent_ButtonPressed():
return buttonPressed(_that.field0,_that.field1);case UserEvent_ButtonReleased():
return buttonReleased(_that.field0,_that.field1);case UserEvent_Click():
return click(_that.field0,_that.field1);case UserEvent_DoubleClick():
return doubleClick(_that.field0,_that.field1);case UserEvent_PointerMoved():
return pointerMoved(_that.field0);case UserEvent_DragStarted():
return dragStarted(_that.field0,_that.field1);case UserEvent_Drag():
return drag(_that.field0,_that.field1,_that.field2);case UserEvent_DragEnded():
return dragEnded(_that.field0,_that.field1);case UserEvent_Scroll():
return scroll(_that.field0,_that.field1);case UserEvent_Zoom():
return zoom(_that.field0,_that.field1);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( MouseButton field0,  MouseEvent field1)?  buttonPressed,TResult? Function( MouseButton field0,  MouseEvent field1)?  buttonReleased,TResult? Function( MouseButton field0,  MouseEvent field1)?  click,TResult? Function( MouseButton field0,  MouseEvent field1)?  doubleClick,TResult? Function( MouseEvent field0)?  pointerMoved,TResult? Function( MouseButton field0,  MouseEvent field1)?  dragStarted,TResult? Function( MouseButton field0,  Vector2 field1,  MouseEvent field2)?  drag,TResult? Function( MouseButton field0,  MouseEvent field1)?  dragEnded,TResult? Function( double field0,  MouseEvent field1)?  scroll,TResult? Function( double field0,  Point2 field1)?  zoom,}) {final _that = this;
switch (_that) {
case UserEvent_ButtonPressed() when buttonPressed != null:
return buttonPressed(_that.field0,_that.field1);case UserEvent_ButtonReleased() when buttonReleased != null:
return buttonReleased(_that.field0,_that.field1);case UserEvent_Click() when click != null:
return click(_that.field0,_that.field1);case UserEvent_DoubleClick() when doubleClick != null:
return doubleClick(_that.field0,_that.field1);case UserEvent_PointerMoved() when pointerMoved != null:
return pointerMoved(_that.field0);case UserEvent_DragStarted() when dragStarted != null:
return dragStarted(_that.field0,_that.field1);case UserEvent_Drag() when drag != null:
return drag(_that.field0,_that.field1,_that.field2);case UserEvent_DragEnded() when dragEnded != null:
return dragEnded(_that.field0,_that.field1);case UserEvent_Scroll() when scroll != null:
return scroll(_that.field0,_that.field1);case UserEvent_Zoom() when zoom != null:
return zoom(_that.field0,_that.field1);case _:
  return null;

}
}

}

/// @nodoc


class UserEvent_ButtonPressed extends UserEvent {
  const UserEvent_ButtonPressed(this.field0, this.field1): super._();
  

@override final  MouseButton field0;
 final  MouseEvent field1;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserEvent_ButtonPressedCopyWith<UserEvent_ButtonPressed> get copyWith => _$UserEvent_ButtonPressedCopyWithImpl<UserEvent_ButtonPressed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UserEvent_ButtonPressed&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0,field1);
}

@override
String toString() {
    return 'UserEvent.buttonPressed(field0: $field0, field1: $field1)';
}


}

/// @nodoc
abstract mixin class $UserEvent_ButtonPressedCopyWith<$Res> implements $UserEventCopyWith<$Res> {
  factory $UserEvent_ButtonPressedCopyWith(UserEvent_ButtonPressed value, $Res Function(UserEvent_ButtonPressed) _then) = _$UserEvent_ButtonPressedCopyWithImpl;
@useResult
$Res call({
 MouseButton field0, MouseEvent field1
});




}
/// @nodoc
class _$UserEvent_ButtonPressedCopyWithImpl<$Res>
    implements $UserEvent_ButtonPressedCopyWith<$Res> {
  _$UserEvent_ButtonPressedCopyWithImpl(this._self, this._then);

  final UserEvent_ButtonPressed _self;
  final $Res Function(UserEvent_ButtonPressed) _then;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,}) {
  return _then(UserEvent_ButtonPressed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as MouseButton,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as MouseEvent,
  ));
}


}

/// @nodoc


class UserEvent_ButtonReleased extends UserEvent {
  const UserEvent_ButtonReleased(this.field0, this.field1): super._();
  

@override final  MouseButton field0;
 final  MouseEvent field1;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserEvent_ButtonReleasedCopyWith<UserEvent_ButtonReleased> get copyWith => _$UserEvent_ButtonReleasedCopyWithImpl<UserEvent_ButtonReleased>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UserEvent_ButtonReleased&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0,field1);
}

@override
String toString() {
    return 'UserEvent.buttonReleased(field0: $field0, field1: $field1)';
}


}

/// @nodoc
abstract mixin class $UserEvent_ButtonReleasedCopyWith<$Res> implements $UserEventCopyWith<$Res> {
  factory $UserEvent_ButtonReleasedCopyWith(UserEvent_ButtonReleased value, $Res Function(UserEvent_ButtonReleased) _then) = _$UserEvent_ButtonReleasedCopyWithImpl;
@useResult
$Res call({
 MouseButton field0, MouseEvent field1
});




}
/// @nodoc
class _$UserEvent_ButtonReleasedCopyWithImpl<$Res>
    implements $UserEvent_ButtonReleasedCopyWith<$Res> {
  _$UserEvent_ButtonReleasedCopyWithImpl(this._self, this._then);

  final UserEvent_ButtonReleased _self;
  final $Res Function(UserEvent_ButtonReleased) _then;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,}) {
  return _then(UserEvent_ButtonReleased(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as MouseButton,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as MouseEvent,
  ));
}


}

/// @nodoc


class UserEvent_Click extends UserEvent {
  const UserEvent_Click(this.field0, this.field1): super._();
  

@override final  MouseButton field0;
 final  MouseEvent field1;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserEvent_ClickCopyWith<UserEvent_Click> get copyWith => _$UserEvent_ClickCopyWithImpl<UserEvent_Click>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UserEvent_Click&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0,field1);
}

@override
String toString() {
    return 'UserEvent.click(field0: $field0, field1: $field1)';
}


}

/// @nodoc
abstract mixin class $UserEvent_ClickCopyWith<$Res> implements $UserEventCopyWith<$Res> {
  factory $UserEvent_ClickCopyWith(UserEvent_Click value, $Res Function(UserEvent_Click) _then) = _$UserEvent_ClickCopyWithImpl;
@useResult
$Res call({
 MouseButton field0, MouseEvent field1
});




}
/// @nodoc
class _$UserEvent_ClickCopyWithImpl<$Res>
    implements $UserEvent_ClickCopyWith<$Res> {
  _$UserEvent_ClickCopyWithImpl(this._self, this._then);

  final UserEvent_Click _self;
  final $Res Function(UserEvent_Click) _then;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,}) {
  return _then(UserEvent_Click(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as MouseButton,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as MouseEvent,
  ));
}


}

/// @nodoc


class UserEvent_DoubleClick extends UserEvent {
  const UserEvent_DoubleClick(this.field0, this.field1): super._();
  

@override final  MouseButton field0;
 final  MouseEvent field1;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserEvent_DoubleClickCopyWith<UserEvent_DoubleClick> get copyWith => _$UserEvent_DoubleClickCopyWithImpl<UserEvent_DoubleClick>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UserEvent_DoubleClick&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0,field1);
}

@override
String toString() {
    return 'UserEvent.doubleClick(field0: $field0, field1: $field1)';
}


}

/// @nodoc
abstract mixin class $UserEvent_DoubleClickCopyWith<$Res> implements $UserEventCopyWith<$Res> {
  factory $UserEvent_DoubleClickCopyWith(UserEvent_DoubleClick value, $Res Function(UserEvent_DoubleClick) _then) = _$UserEvent_DoubleClickCopyWithImpl;
@useResult
$Res call({
 MouseButton field0, MouseEvent field1
});




}
/// @nodoc
class _$UserEvent_DoubleClickCopyWithImpl<$Res>
    implements $UserEvent_DoubleClickCopyWith<$Res> {
  _$UserEvent_DoubleClickCopyWithImpl(this._self, this._then);

  final UserEvent_DoubleClick _self;
  final $Res Function(UserEvent_DoubleClick) _then;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,}) {
  return _then(UserEvent_DoubleClick(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as MouseButton,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as MouseEvent,
  ));
}


}

/// @nodoc


class UserEvent_PointerMoved extends UserEvent {
  const UserEvent_PointerMoved(this.field0): super._();
  

@override final  MouseEvent field0;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserEvent_PointerMovedCopyWith<UserEvent_PointerMoved> get copyWith => _$UserEvent_PointerMovedCopyWithImpl<UserEvent_PointerMoved>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UserEvent_PointerMoved&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'UserEvent.pointerMoved(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $UserEvent_PointerMovedCopyWith<$Res> implements $UserEventCopyWith<$Res> {
  factory $UserEvent_PointerMovedCopyWith(UserEvent_PointerMoved value, $Res Function(UserEvent_PointerMoved) _then) = _$UserEvent_PointerMovedCopyWithImpl;
@useResult
$Res call({
 MouseEvent field0
});




}
/// @nodoc
class _$UserEvent_PointerMovedCopyWithImpl<$Res>
    implements $UserEvent_PointerMovedCopyWith<$Res> {
  _$UserEvent_PointerMovedCopyWithImpl(this._self, this._then);

  final UserEvent_PointerMoved _self;
  final $Res Function(UserEvent_PointerMoved) _then;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(UserEvent_PointerMoved(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as MouseEvent,
  ));
}


}

/// @nodoc


class UserEvent_DragStarted extends UserEvent {
  const UserEvent_DragStarted(this.field0, this.field1): super._();
  

@override final  MouseButton field0;
 final  MouseEvent field1;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserEvent_DragStartedCopyWith<UserEvent_DragStarted> get copyWith => _$UserEvent_DragStartedCopyWithImpl<UserEvent_DragStarted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UserEvent_DragStarted&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0,field1);
}

@override
String toString() {
    return 'UserEvent.dragStarted(field0: $field0, field1: $field1)';
}


}

/// @nodoc
abstract mixin class $UserEvent_DragStartedCopyWith<$Res> implements $UserEventCopyWith<$Res> {
  factory $UserEvent_DragStartedCopyWith(UserEvent_DragStarted value, $Res Function(UserEvent_DragStarted) _then) = _$UserEvent_DragStartedCopyWithImpl;
@useResult
$Res call({
 MouseButton field0, MouseEvent field1
});




}
/// @nodoc
class _$UserEvent_DragStartedCopyWithImpl<$Res>
    implements $UserEvent_DragStartedCopyWith<$Res> {
  _$UserEvent_DragStartedCopyWithImpl(this._self, this._then);

  final UserEvent_DragStarted _self;
  final $Res Function(UserEvent_DragStarted) _then;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,}) {
  return _then(UserEvent_DragStarted(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as MouseButton,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as MouseEvent,
  ));
}


}

/// @nodoc


class UserEvent_Drag extends UserEvent {
  const UserEvent_Drag(this.field0, this.field1, this.field2): super._();
  

@override final  MouseButton field0;
 final  Vector2 field1;
 final  MouseEvent field2;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserEvent_DragCopyWith<UserEvent_Drag> get copyWith => _$UserEvent_DragCopyWithImpl<UserEvent_Drag>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UserEvent_Drag&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1)&&(identical(other.field2, field2) || other.field2 == field2));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0,field1,field2);
}

@override
String toString() {
    return 'UserEvent.drag(field0: $field0, field1: $field1, field2: $field2)';
}


}

/// @nodoc
abstract mixin class $UserEvent_DragCopyWith<$Res> implements $UserEventCopyWith<$Res> {
  factory $UserEvent_DragCopyWith(UserEvent_Drag value, $Res Function(UserEvent_Drag) _then) = _$UserEvent_DragCopyWithImpl;
@useResult
$Res call({
 MouseButton field0, Vector2 field1, MouseEvent field2
});




}
/// @nodoc
class _$UserEvent_DragCopyWithImpl<$Res>
    implements $UserEvent_DragCopyWith<$Res> {
  _$UserEvent_DragCopyWithImpl(this._self, this._then);

  final UserEvent_Drag _self;
  final $Res Function(UserEvent_Drag) _then;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,Object? field2 = null,}) {
  return _then(UserEvent_Drag(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as MouseButton,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as Vector2,null == field2 ? _self.field2 : field2 // ignore: cast_nullable_to_non_nullable
as MouseEvent,
  ));
}


}

/// @nodoc


class UserEvent_DragEnded extends UserEvent {
  const UserEvent_DragEnded(this.field0, this.field1): super._();
  

@override final  MouseButton field0;
 final  MouseEvent field1;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserEvent_DragEndedCopyWith<UserEvent_DragEnded> get copyWith => _$UserEvent_DragEndedCopyWithImpl<UserEvent_DragEnded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UserEvent_DragEnded&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0,field1);
}

@override
String toString() {
    return 'UserEvent.dragEnded(field0: $field0, field1: $field1)';
}


}

/// @nodoc
abstract mixin class $UserEvent_DragEndedCopyWith<$Res> implements $UserEventCopyWith<$Res> {
  factory $UserEvent_DragEndedCopyWith(UserEvent_DragEnded value, $Res Function(UserEvent_DragEnded) _then) = _$UserEvent_DragEndedCopyWithImpl;
@useResult
$Res call({
 MouseButton field0, MouseEvent field1
});




}
/// @nodoc
class _$UserEvent_DragEndedCopyWithImpl<$Res>
    implements $UserEvent_DragEndedCopyWith<$Res> {
  _$UserEvent_DragEndedCopyWithImpl(this._self, this._then);

  final UserEvent_DragEnded _self;
  final $Res Function(UserEvent_DragEnded) _then;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,}) {
  return _then(UserEvent_DragEnded(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as MouseButton,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as MouseEvent,
  ));
}


}

/// @nodoc


class UserEvent_Scroll extends UserEvent {
  const UserEvent_Scroll(this.field0, this.field1): super._();
  

@override final  double field0;
 final  MouseEvent field1;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserEvent_ScrollCopyWith<UserEvent_Scroll> get copyWith => _$UserEvent_ScrollCopyWithImpl<UserEvent_Scroll>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UserEvent_Scroll&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0,field1);
}

@override
String toString() {
    return 'UserEvent.scroll(field0: $field0, field1: $field1)';
}


}

/// @nodoc
abstract mixin class $UserEvent_ScrollCopyWith<$Res> implements $UserEventCopyWith<$Res> {
  factory $UserEvent_ScrollCopyWith(UserEvent_Scroll value, $Res Function(UserEvent_Scroll) _then) = _$UserEvent_ScrollCopyWithImpl;
@useResult
$Res call({
 double field0, MouseEvent field1
});




}
/// @nodoc
class _$UserEvent_ScrollCopyWithImpl<$Res>
    implements $UserEvent_ScrollCopyWith<$Res> {
  _$UserEvent_ScrollCopyWithImpl(this._self, this._then);

  final UserEvent_Scroll _self;
  final $Res Function(UserEvent_Scroll) _then;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,}) {
  return _then(UserEvent_Scroll(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as double,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as MouseEvent,
  ));
}


}

/// @nodoc


class UserEvent_Zoom extends UserEvent {
  const UserEvent_Zoom(this.field0, this.field1): super._();
  

@override final  double field0;
 final  Point2 field1;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserEvent_ZoomCopyWith<UserEvent_Zoom> get copyWith => _$UserEvent_ZoomCopyWithImpl<UserEvent_Zoom>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UserEvent_Zoom&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0,field1);
}

@override
String toString() {
    return 'UserEvent.zoom(field0: $field0, field1: $field1)';
}


}

/// @nodoc
abstract mixin class $UserEvent_ZoomCopyWith<$Res> implements $UserEventCopyWith<$Res> {
  factory $UserEvent_ZoomCopyWith(UserEvent_Zoom value, $Res Function(UserEvent_Zoom) _then) = _$UserEvent_ZoomCopyWithImpl;
@useResult
$Res call({
 double field0, Point2 field1
});




}
/// @nodoc
class _$UserEvent_ZoomCopyWithImpl<$Res>
    implements $UserEvent_ZoomCopyWith<$Res> {
  _$UserEvent_ZoomCopyWithImpl(this._self, this._then);

  final UserEvent_Zoom _self;
  final $Res Function(UserEvent_Zoom) _then;

/// Create a copy of UserEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,}) {
  return _then(UserEvent_Zoom(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as double,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as Point2,
  ));
}


}

// dart format on
