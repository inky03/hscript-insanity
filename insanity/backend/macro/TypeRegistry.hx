package insanity.backend.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;
#end

import insanity.backend.Tools;

typedef TypeInfo = {
	var kind:String;
	var name:String;
	var module:String;
	var pack:Array<String>;
	
	var ?isInterface:Bool;
	
	var ?typedefType:TypeInfo;
}

typedef TypeMap = {
	var byCompilePath:Map<String, Array<TypeInfo>>;
	var byPackage:Map<String, Array<TypeInfo>>;
	var byModule:Map<String, Array<TypeInfo>>;
	var byPath:Map<String, Array<TypeInfo>>;
	var all:Array<TypeInfo>;
}

class TypeRegistry {
	static macro function build() {
		var cls:String = 'insanity.backend.macro.TypeRegistry';
		
		Context.onAfterTyping(function(types) {
			var self = TypeTools.getClass(Context.getType(cls));
			var _c:Map<String, Dynamic> = [];
			var map:Array<Dynamic> = [];
			
			function findTypeInfo(m:String, s:String) {
				return _c['$m.$s'];
			}
			function makeTypeInfo(k:String, d:Dynamic) {
				var info:TypeInfo = (findTypeInfo(d.module, d.name) ?? {kind: k, module: d.module, name: d.name, pack: d.pack});
				if (k == 'typedef') {
					info.typedefType = switch (d.type) {
						case TInst(r, _): makeTypeInfo('class', r.get());
						default: null;
					}
				}
				if (d.isInterface) {
					info.isInterface = true;
				}
				_c['${d.module}.${d.name}'] = info;
				return info;
			}
			
			for (type in types) {
				map.push(switch (type) {
					case TClassDecl(r): makeTypeInfo('class', r.get());
					case TEnumDecl(r): makeTypeInfo('enum', r.get());
					case TTypeDecl(r): makeTypeInfo('typedef', r.get());
					case TAbstract(r): makeTypeInfo('abstract', r.get());
				});
			}
			
			self.meta.remove('types');
            self.meta.add('types', [macro $v {map}], self.pos);
			// Context.info('types registered !!', Context.currentPos());
		});
		
		return macro {
			var meta:Array<TypeInfo> = cast haxe.rtti.Meta.getType($p {cls.split('.')}).types[0];
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
	
	static var _types(default, null):TypeMap #if (!macro) = build() #end ;
	
	public inline static function fromPath(path:String):Array<TypeInfo> { return _types.byPath.get(path); }
	public inline static function fromModule(path:String):Array<TypeInfo> { return _types.byModule.get(path); }
	public inline static function fromPackage(path:String):Array<TypeInfo> { return _types.byPackage.get(path); }
	public inline static function fromCompilePath(path:String):Array<TypeInfo> { return _types.byCompilePath.get(path); }
	
	public static function compilePath(info:TypeInfo):String {
		var typePath:Array<String> = info.pack.copy();
		typePath.push(info.name);
		return typePath.join('.');
	}
	public static function fullPath(info:TypeInfo):String {
		return (info.module + (info.module.length > 0 ? '.' : '') + info.name);
	}
	public static function resolve(info:TypeInfo):Dynamic {
		if (info.typedefType != null)
			return Tools.resolve(compilePath(info.typedefType));
		return Tools.resolve(compilePath(info));
	}
}