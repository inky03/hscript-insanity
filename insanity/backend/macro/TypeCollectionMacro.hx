package insanity.backend.macro;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.ExprTools;
import haxe.macro.TypedExprTools;
#end

import insanity.backend.TypeCollection;

class TypeCollectionMacro {
	static var _name:String = 'insanity.backend.macro.TypeCollectionMacro';
	
	public static macro function build() {
		Context.onAfterTyping(function(types) {
			var self = TypeTools.getClass(Context.getType(_name));
			if (self.meta.has('typed')) return;
			
			var _c:Map<String, Dynamic> = [];
			var map:Array<Dynamic> = [];
			
			inline function varAccessToString(access:VarAccess, dyn:String) {
				return switch (access) {
					default: null;
					
					case AccNormal: 'default';
					case AccNever: 'never';
					case AccNo: 'null';
					case AccCall: dyn;
				}
			}
			function findTypeInfo(m:String, s:String) {
				return _c['$m.$s'];
			}
			/*function typeToAbstractTypeCast(type:Type):AbstractTypeCast {
				return switch (type) {
					case TMono(r): typeToAbstractTypeCast(r.get());
					case TEnum(r, _): ATType(r.get().name);
					case TInst(r, _): ATType(r.get().name);
					case TType(r, _): typeToAbstractTypeCast(r.get().type);
					case TFun(_, _): ATMethod;
					case TLazy(f): typeToAbstractTypeCast(f());
					case TAbstract(r, _): ATType(r.get().name);
					case TDynamic(t): (t != null ? typeToAbstractTypeCast(t) : ATDynamic);
					case TAnonymous(_): ATStruct;
				}
			}*/
			function getTypeInfo(type:ModuleType) {
				function makeTypeInfo(k:String, d:Dynamic) {
					var info:TypeInfo = (findTypeInfo(d.module, d.name) ?? {kind: k, module: d.module, name: d.name, pack: d.pack});
					
					if (k == 'typedef') {
						info.typedefType = switch (d.type) {
							case TInst(r, _): makeTypeInfo('class', r.get());
							default: null;
						}
					} else if (k == 'abstract') {
						/*var path = d.module.split('.');
						if (path.length > 0) path[path.length - 1] = '_${path[path.length - 1]}';
						path.push('${d.name}_Impl_');
						
						var ab = (info.abstractImpl = {
							internalName: path.join('.'),
							staticMethods: [],
							properties: [],
							
							fromMethods: [],
							toMethods: [],
							
							overloadMethods: [],
							commutativeOverloads: []
						});
						
						final d:AbstractType = cast d;
						
						if (d.name == 'FlxColor') {
							for (field in d.impl.get().statics.get())
								trace(field.name);
							//trace(d.impl.get().fields.get());
							//trace(d.impl.get().statics.get());
							for (field in d.array) {
								trace(field);
							}
							for (field in d.binops) {
								trace(field);
							}
							for (field in d.unops) {
								trace(field);
							}
							for (to in d.to) {
								ab.toMethods.set(typeToAbstractTypeCast(to.t), to.field?.name);
							}
							for (from in d.from) {
								ab.fromMethods.set(typeToAbstractTypeCast(from.t), from.field?.name);
							}
							
							trace(ab);
						}
						*/
					}
					
					if (d.isInterface) {
						info.isInterface = true;
						info.interfaceFields = [];
						info.interfaceMethods = [];
						
						var fields:Array<ClassField> = d.fields.get();
						for (field in fields) {
							switch (field.kind) {
								case FVar(get, set):
									info.interfaceFields.push({
										name: field.name,
										isFinal: field.isFinal,
										isPublic: false, //field.isPublic doesnt seem to be accurate ...
										
										get: varAccessToString(get, 'get'),
										set: varAccessToString(set, 'set')
									});
									
								case FMethod(kind):
									info.interfaceMethods.push({
										name: field.name,
										isPublic: false,
										
										isDynamic: (kind == MethDynamic),
										argumentCount: switch (field.type) {
											default: throw '???';
											case TFun(args, _): args.length;
										}
									});
							}
						}
					}
					
					_c['${d.module}.${d.name}'] = info;
					
					return info;
				}
				
				return switch (type) {
					case TClassDecl(r): return makeTypeInfo('class', r.get());
					case TEnumDecl(r): return makeTypeInfo('enum', r.get());
					case TTypeDecl(r): return makeTypeInfo('typedef', r.get());
					case TAbstract(r): return makeTypeInfo('abstract', r.get());
				};
			}
			
			for (type in types)
				map.push(getTypeInfo(type));
			
			self.meta.add('typed', [macro $v {haxe.Serializer.run(map)}], self.pos);
			// Context.info('types registered !!', Context.currentPos());
		});
		
		return macro {
			var meta:Array<TypeInfo> = cast haxe.Unserializer.run(haxe.rtti.Meta.getType($p {_name.split('.')}).typed[0]);
			var map:TypeMap = { byPackage: [], byModule: [], byPath: [], byCompilePath: [], all: [] };
			
			for (info in meta) {
				var tp:Array<String> = info.pack.copy(); tp.push(info.name);
				var packPath:String = info.pack.join('.');
				
				map.all.push(info);
				
				map.byCompilePath[tp.join('.')] = [info];
				map.byPath[info.module + (info.module.length == 0 ? '' : '.') + info.name] = [info];
				
				map.byModule[info.module] ??= new Array<TypeInfo>();
				map.byPackage[packPath] ??= new Array<TypeInfo>();
				
				map.byModule[info.module].push(info);
				map.byPackage[packPath].push(info);
			}
				
			cast map;
		}
	}
}