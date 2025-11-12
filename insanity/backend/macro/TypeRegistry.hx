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
}

typedef TypeMap = {
	var byPackage:Map<String, Array<TypeInfo>>;
	var byModule:Map<String, Array<TypeInfo>>;
	var byPath:Map<String, Array<TypeInfo>>;
}

class TypeRegistry {
	static macro function build() {
		var cls:String = 'insanity.backend.macro.TypeRegistry';
		
		Context.onAfterTyping(function(types) {
			var self = TypeTools.getClass(Context.getType(cls));
			var map:Array<Dynamic> = [];
			
			function addType(t:String, d:Dynamic) {
				map.push({kind: t, module: d.module, name: d.name, pack: d.pack});
			}
			
			for (type in types) {
				switch (type) {
					case TClassDecl(r): addType('class', r.get());
					case TEnumDecl(r): addType('enum', r.get());
					case TTypeDecl(r): addType('type', r.get());
					case TAbstract(r): addType('abstract', r.get());
				}
			}
			
			self.meta.remove('types');
            self.meta.add('types', [macro $v {map}], self.pos);
			// Context.info('types registered !!', Context.currentPos());
		});
		
		return macro {
			var meta:Array<TypeInfo> = cast haxe.rtti.Meta.getType($p {cls.split('.')}).types[0];
			var map:TypeMap = { byPackage: [], byModule: [], byPath: [] }
			
			for (info in meta) {
				var tp:Array<String> = info.pack.copy(); tp.push(info.name);
				var packPath:String = info.pack.join('.');
				
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
	
	public static function path(info:TypeInfo):String {
		var typePath:Array<String> = info.pack.copy();
		typePath.push(info.name);
		return typePath.join('.');
	}
	public static function resolve(info:TypeInfo):Dynamic {
		return Tools.resolve(path(info));
	}
}