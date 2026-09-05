package insanity.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using Lambda;
using StringTools;
using haxe.macro.TypeTools;
using haxe.macro.ExprTools;
using haxe.macro.ComplexTypeTools;
#end

class ScriptableMacro {
	public static var ignoreFields:Map<String, Bool> = [for (f in [
		'reflectHasField', 'reflectGetField', 'reflectSetField', 'reflectListFields', 'reflectGetProperty', 'reflectSetProperty',
		'typeCreateInstance', 'typeGetClass', 'typeGetClassFields', 'typeCreateEmptyInstance', 'typeGetInstanceFields',
		'__isScripted', '__scriptedBase', '__interpSafe', '__interp', '__func', '__fields', '__vars', '__instanceFields','instanceFields', 'inlinedFields', 'new', 'super'
	]) f => true];
	
	static var scriptableClasses:Array<String> = [];
	static var generated:Int = 0;
	
	#if macro
	/**
	 * Injects the HscriptInsanity interpreter into a class and its fields to make it extendable in Hscript.
	 * If used, this build macro should be added to every class and not filtered with `Compiler.addGlobalMetadata`, using the function's `exclude` and `unless` parameters instead
	 * to prevent compilation failure.
	 * 
	 * @param	exclude		Classes with paths starting with the specified prefixes, and all of their subclasses, will be ignored
	 * @param	unless		Classes with paths starting with the specified prefixes will be unexcluded, if you need to cherry pick (This won't work in subclasses of ignored classes!)
	 * @param	filter		Function to filter classes, if you need to cherry pick. The compile path of the class will be passed to this function. Returning `false` will exclude the class
	 * @param	evil		Whether to allow scripted classes to override inlined fields or not.
	 * @param	superEvil	Whether to allow scripted classes to extend private classes or not.
	 * 
	 * @return	Context fields
	 */
	@:access(insanity.macro.Patcher)
	public static macro function buildScriptable(?exclude:Array<String>, ?unless:Array<String>, ?filter:String -> Bool, evil:Bool = false, superEvil:Bool = false):Array<Field> {
		if (Context.defined('display')) return Context.getBuildFields();
		
		if (Context.defined('insanity.noScriptableTypes')) {
			Insanity.beginLog('${Insanity.ansiEsc}49;31mScriptableMacro.buildScriptable${Insanity.ansiEsc}0m Scriptable types were disabled in this project! Won\'t inject any classes', Insanity.blobError);
			return Context.getBuildFields();
		}
		
		Insanity.beginLog('Applying ScriptableMacro.buildScriptable');
		Insanity.finishLog['ScriptableMacro.buildScriptable'] ??= () -> {
			var str:String = 'Injected $generated classes';
			
			if (Insanity.isVerbose()) str += ' (omitted ${omitted} | excluded ${excluded})';
			
			str;
		};
		
		var fields:Array<Field> = buildHscript(exclude ?? [], unless ?? [], filter);
		if (fields == null) return Context.getBuildFields();
		
		var cls = Context.getLocalClass()?.get();
		var pos = Context.currentPos();
		
		function isEligible(cls:ClassType):Bool { // about time (nvm i didnt even use it anywher else)
			if (cls == null || !cls.meta.has(':insanityScriptable')) return false;
			
			if (!superEvil && Insanity.classIsPrivate(cls)) {
				omitted ++;
				
				if (Insanity.isVerbose()) {
					var path:Array<String> = cls.pack.copy(); path.push(cls.name);
					
					haxe.Log.trace('${Insanity.blob} ${Insanity.ansiEsc}49;32mScriptableMacro.buildScriptable${Insanity.ansiEsc}0m OMITTED ${path.join('.')} (private class)', null);
				}
				
				// trace('private ${cls.pack.join('.') + '.' + cls.name}');
				return false;
			}
			
			switch (cls.kind) {
				case KGeneric:
					omitted ++;
					
					if (Insanity.isVerbose()) {
						var path:Array<String> = cls.pack.copy(); path.push(cls.name);
						
						haxe.Log.trace('${Insanity.blob} ${Insanity.ansiEsc}49;32mScriptableMacro.buildScriptable${Insanity.ansiEsc}0m OMITTED ${path.join('.')} (generic class)', null);
					}
					
					return false;
					
				default:
			}
			
			return true;
		}
		
		if (!isEligible(cls)) return fields;
		
		var hasToString:Bool = false;
		var knownFields:Map<String, Bool> = [];
		var inlinedFields:Map<String, Bool> = [];
		
		cls.meta.remove(':insanityScriptable');
		cls.meta.add(':insanityScriptable', [macro true], pos);
		cls.meta.add(':access', [macro insanity.backend.Interp], pos);
		cls.meta.add(':access', [macro insanity.backend.types.InsanityScriptedClass], pos);
		
		var superName:String = switch(cls.meta.extract(':insanitySuperName').pop().params[0].expr) {
			case EConst(CString(s)): s;
			default: throw '???';
		}
		
		var su = cls.superClass?.t.get();
		var addFields:Bool = (cls.superClass == null);
		
		while (true) {
			if (su == null) break;
			
			if (!superEvil && Insanity.classIsPrivate(su)) {
				omitted ++;
				
				if (Insanity.isVerbose()) {
					var path:Array<String> = cls.pack.copy(); path.push(cls.name);
					
					haxe.Log.trace('${Insanity.blob} ${Insanity.ansiEsc}49;32mScriptableMacro.buildScriptable${Insanity.ansiEsc}0m OMITTED ${path.join('.')} (extends private class)', null);
				}
				
				return fields;
			}
			
			for (field in su.statics.get()) {
				if (field.name == 'toString') hasToString = true;
			}
			
			for (field in su.fields.get()) {
				knownFields.set(field.name, true);
				
				if (field.name == 'toString') hasToString = true;
				
				switch (field.kind) {
					case FMethod(MethInline) if (!evil):
						inlinedFields.set(field.name, true);
					
					default:
				}
			}
			
			su = su.superClass?.t.get();
		}
		
		for (field in fields) {
			final f:String = field.name;
			
			if (f == 'toString') hasToString = true;
			if (f.contains('insanitySuper') || ignoreFields.exists(f)) continue;
			
			final isStatic:Bool = (field?.access.contains(AStatic));
			
			if (!isStatic) knownFields.set(f, true);
			
			if (field?.access.contains(AInline) && !evil) {
				if (!isStatic) inlinedFields.set(f, true);
				
				continue;
			}
			
			switch (field.kind) {
				default:
				case FFun(fun) if (!isStatic):
					// trace(f + ' - ' + field.access);
					var isVoid:Bool = (fun.ret == null || fun.ret.match(TPath({name: 'Void', pack: _})));
					
					if (isVoid) {
						function checkVoid(expr:Expr):Void {
							if (expr == null) return;
							
							switch (expr.expr) {
								case EFunction(_, _): expr;
								case EReturn(e) if (e != null): isVoid = false;
								default: expr.iter(checkVoid);
							}
						}
						
						checkVoid(fun.expr);
					}
					
					fun.expr = scriptableExpr(fun.expr, f, [for (arg in fun.args) macro $i {arg.name}], isVoid);
					
					if (f == 'toString' && !addFields && !field.access?.contains(AOverride)) {
						field.access ??= [];
						field.access.push(AOverride);
					}
			}
		}
		
		var path:Array<String> = cls.pack.copy(); path.push(cls.name);
		
		if (Insanity.isVerbose()) haxe.Log.trace('${Insanity.blob} ${Insanity.ansiEsc}49;32mScriptableMacro.buildScriptable${Insanity.ansiEsc}0m ${path.join('.')}', null);
		
		if (!hasToString) {
			fields.push({
				pos: pos, access: (addFields ? [APublic] : [APublic, AOverride]), name: 'toString',
				kind: FFun({
					args: [],
					expr: scriptableExpr(macro return (__isScripted ? __scriptedBase.path : __classString), 'toString', []),
					ret: macro:String
				})
			});
		}
		
		var ii = {pos: cls.pos, expr: EConst(CIdent(superName))};
		var newExpr = macro {
			__instanceFields = instanceFields;
			
			__vars = [];
			__func = '';
			__isScripted = true;
			__classString = base.path;
			
			__scriptedBase = base;
			__interpSafe = base.safe;
			__interp = Type.createInstance(insanity.Config.interpClass, [base.interp.environment, this]);
			__interp.pushStack(insanity.backend.CallStack.StackItem.SModule(base.module?.path ?? base.name));
			
			__interp.setDefaults(false, false);
			__interp.variables.set('this', this);
			__interp.variables.set('interp', __interp);
			
			for (u in base.interp.usings) __interp.usings.push(u);
			for (k => i in base.interp.imports) __interp.imports.set(k, i);
			for (k => v in base.interp.variables) if (!__interp.variables.exists(k)) __interp.variables.set(k, v);
			
			var superConstr = $ii;
			
			__fields = [];
			var constructor:Dynamic = null;
			function setInstanceFields(i:Dynamic) {
				var instanceFields:Map<String, Bool> = i.instanceFields;
				if (instanceFields == null) return;
				
				var superLocals:Map<String, insanity.backend.Interp.Variable> = __interp.duplicate(__interp.locals);
				
				for (field in instanceFields.keys()) {
					if (insanity.macro.ScriptableMacro.ignoreFields.exists(field)) continue;
					
					if (!__interp.variables.exists(field)) __interp.variables.set(field, insanity.backend.Expr.Mirror.MProperty(this, field));
					
					var f = Reflect.field(this, field);
					if (Reflect.isFunction(f)) superLocals.set(field, {r: f});
				}
				
				__interp.locals.set('super', {r: insanity.backend.Expr.Mirror.MSuper(superLocals, superConstr)});
			}
			function setFields(t:insanity.backend.types.Scripted.InsanityScriptedClass, isSuper:Bool = false) {
				for (field in t.decl.fields) {
					var f:String = field.name;
					
					if (f == 'new' || field.access.contains(AStatic)) continue;
					
					switch (field.kind) {
						case KFunction(fun):
							__interp.locals.set(f, {r: null, access: field.access});
							
						case KVar(v):
							if (__instanceFields.exists(f)) {
								Reflect.setField(this, f, __interp.exprReturn(v.expr));
							} else {
								final l:insanity.backend.Interp.Variable = {r: null, access: field.access, get: v.get, set: v.set};
								if (v.get != null) l.get = v.get;
								if (v.set != null) l.set = v.set;
								
								__interp.locals.set(f, l);
							}
					}
				}
				
				var superLocals:Map<String, insanity.backend.Interp.Variable> = __interp.duplicate(__interp.locals);
				for (loc => v in t.__vars)
					superLocals.set(loc, v);
				
				var instanceFields:Map<String, Bool> = t.extending?.instanceFields;
				if (instanceFields != null) {
					for (field in instanceFields.keys()) {
						if (insanity.macro.ScriptableMacro.ignoreFields.exists(field)) continue;
						
						if (!__interp.variables.exists(field)) __interp.variables.set(field, insanity.backend.Expr.Mirror.MProperty(this, field));
						
						var f = Reflect.field(this, field);
						if (Reflect.isFunction(f)) superLocals.set(field, {r: f});
					}
				}
				
				for (field in t.decl.fields) {
					var f:String = field.name;
					
					if (field.access.contains(AStatic)) continue;
					if (f != 'new') __fields.push(f);
					
					switch (field.kind) {
						case KFunction(fun):
							if (f == 'new') {
								constructor = __interp.buildFunction(f, fun.args, fun.expr, fun.ret, superLocals, true);
								continue;
							}
							
							__interp.locals.get(f).r = __interp.buildFunction(f, fun.args, fun.expr, fun.ret, superLocals);
							
						case KVar(v):
							if (__interp.locals.exists(f))
								__interp.locals.get(f).r = (v.expr == null ? null : __interp.exprReturn(v.expr, v.type));
					}
					
					__vars.set(f, __interp.locals.get(f));
					superLocals.set(f, __interp.locals.get(f));
				}
				
				if (isSuper) __interp.locals.set('super', {r: insanity.backend.Expr.Mirror.MSuper(superLocals, constructor)});
			}
			
			function setSuperFields(extending:Dynamic) {
				if (extending is insanity.backend.types.Scripted.InsanityScriptedClass) {
					var extend:insanity.backend.types.Scripted.InsanityScriptedClass = cast extending;
					
					if (extend.extending != null) setSuperFields(extend.extending);
					
					setFields(extend, true);
				} else if (extending != null) {
					setInstanceFields(extending);
				}
			}
			
			setSuperFields(base.extending);
			setFields(base);
			
			constructor ??= superConstr;
			
			__interp.inTry = __interpSafe;
			
			if (__interpSafe) {
				try {
					Reflect.callMethod(this, constructor, arguments);
				} catch (e) {
					base.onInstanceError(e, 'new', this);
				}
			} else {
				Reflect.callMethod(this, constructor, arguments);
			}
		};
		
		fields = fields.concat([{
			pos: pos, name: 'insanityNew',
			access: (addFields ? [] : [AOverride]),
			kind: FFun({
				ret: macro:Void,
				args: [{name: 'base', type: macro:insanity.backend.types.Scripted.InsanityScriptedClass}, {name: 'arguments', type: macro:Array<Dynamic>}],
				expr: newExpr
			})
		}, {
			pos: pos, access: [AStatic, APublic], name: 'instanceFields',
			kind: FVar(macro:Map<String, Bool>, macro $v {knownFields})
		}, {
			pos: pos, access: [AStatic, APublic], name: 'inlinedFields',
			kind: FVar(macro:Map<String, Bool>, macro $v {inlinedFields})
		}]);
		
		if (addFields) {
			// trace(cls.name);
			fields = fields.concat([{
				pos: pos, name: '__instanceFields',
				kind: FVar(macro:Map<String, Bool>, macro null)
			}, {
				pos: pos, name: '__isScripted',
				kind: FVar(macro:Bool, macro false)
			}, {
				pos: pos, name: '__classString',
				kind: FVar(macro:String, macro $v {path.join('.')})
			}, {
				pos: pos, name: '__scriptedBase',
				kind: FVar(macro:Null<insanity.backend.types.Scripted.InsanityScriptedClass>, macro null)
			}, {
				pos: pos, name: '__interpSafe',
				kind: FVar(macro:Bool, macro false)
			}, {
				pos: pos, name: '__interp',
				kind: FVar(macro:Null<insanity.backend.Interp>, macro null)
			}, {
				pos: pos, name: '__func',
				kind: FVar(macro:Null<String>, macro null)
			}, {
				pos: pos, name: '__vars',
				kind: FVar(macro:Map<String, insanity.backend.Interp.Variable>, macro null),
			}, {
				pos: pos, name: '__fields',
				kind: FVar(macro:Array<String>, macro null),
			}, {
				pos: pos, access: [APublic], name: 'reflectHasField',
				kind: FFun({
					args: [{name: 'field', type: macro:String}],
					expr: macro {
						if (insanity.macro.ScriptableMacro.ignoreFields.exists(field)) return false;
						return (__instanceFields.exists(field) || Reflect.hasField(this, field) || __vars.exists(field));
					},
					ret: macro:Bool
				})
			}, {
				pos: pos, access: [APublic], name: 'reflectGetField',
				kind: FFun({
					args: [{name: 'field', type: macro:String}],
					expr: macro {
						if (insanity.macro.ScriptableMacro.ignoreFields.exists(field)) return null;
						if (__instanceFields.exists(field) || Reflect.hasField(this, field)) {
							return Reflect.field(this, field);
						} else if (__vars.exists(field)) {
							return __vars.get(field).r;
						}
						return null;
					},
					ret: macro:Dynamic
				})
			}, {
				pos: pos, access: [APublic], name: 'reflectSetField',
				kind: FFun({
					args: [{name: 'field', type: macro:String}, {name: 'value', type: macro:Dynamic}],
					expr: macro {
						if (insanity.macro.ScriptableMacro.ignoreFields.exists(field)) return null;
						if (__instanceFields.exists(field) || Reflect.hasField(this, field)) {
							Reflect.setField(this, field, value);
							return Reflect.field(this, field);
						} else if (__vars.exists(field)) {
							return __vars.get(field).r = value;
						}
						return null;
					},
					ret: macro:Dynamic
				})
			}, {
				pos: pos, access: [APublic], name: 'reflectGetProperty',
				kind: FFun({
					args: [{name: 'property', type: macro:String}],
					expr: macro {
						if (insanity.macro.ScriptableMacro.ignoreFields.exists(property)) return null;
						if (__instanceFields.exists(property) || Reflect.hasField(this, property)) {
							return Reflect.getProperty(this, property);
						} else if (__vars.exists(property)) {
							return __interp.getLocal(property, __vars);
						}
						return null;
					},
					ret: macro:Dynamic
				})
			}, {
				pos: pos, access: [APublic], name: 'reflectSetProperty',
				kind: FFun({
					args: [{name: 'property', type: macro:String}, {name: 'value', type: macro:Dynamic}],
					expr: macro {
						if (insanity.macro.ScriptableMacro.ignoreFields.exists(property)) return null;
						if (__instanceFields.exists(property) || Reflect.hasField(this, property)) {
							Reflect.setProperty(this, property, value);
							return Reflect.field(this, property);
						} else if (__vars.exists(property)) {
							return __interp.setLocal(property, value, __vars);
						}
						return null;
					},
					ret: macro:Dynamic
				})
			}, {
				pos: pos, access: [APublic], name: 'reflectListFields',
				kind: FFun({
					args: [],
					expr: macro {
						var fields:Array<String> = [for (f in Reflect.fields(this)) if (!insanity.macro.ScriptableMacro.ignoreFields.exists(f)) f];
						for (f in __vars.keys()) { if (!insanity.macro.ScriptableMacro.ignoreFields.exists(f) && !fields.contains(f)) fields.push(f); }
						return fields;
					},
					ret: macro:Array<String>
				})
			}, {
				pos: pos, access: [APublic], name: 'typeGetClass',
				kind: FFun({
					args: [],
					expr: macro return __scriptedBase,
					ret: macro:insanity.backend.types.Scripted.InsanityScriptedClass
				})
			}]);
		}
		
		// trace('make ${cls.pack.join('.')}.${cls.name} scriptable');
		
		scriptableClasses.push(path.join('.'));
		generated ++;
		
		return fields;
	}
	
	static inline function scriptableExpr(oldExpr:Expr, field:String, argsArray:Array<Expr>, isVoid:Bool = false):Expr {
		return macro {
			final fname:String = $v {field};
			
			if (__isScripted && __func != fname && __interp.locals.exists(fname)) {
				final prevFunc:String = __func;
				__func = fname; // prevent loop
				
				var r:Dynamic = null;
				if (__interpSafe) {
					try {
						r = Reflect.callMethod(__interp, __interp.locals.get(fname).r, $a {argsArray});
					} catch (e) {
						__scriptedBase.onInstanceError(e, fname, this);
					}
				} else {
					r = Reflect.callMethod(__interp, __interp.locals.get(fname).r, $a {argsArray});
				}
				
				__func = prevFunc;
				${isVoid ? macro return : macro return cast r};
			} else $oldExpr;
		}
	}
	
	static var omitted:Int = 0;
	static var excluded:Int = 0;
	static function buildHscript(exclude:Array<String>, unless:Array<String>, ?filter:String -> Bool):Array<Field> {
		if (Context.defined('display')) return Context.getBuildFields();
		
		var fields:Array<Field> = Context.getBuildFields();
		var cls:ClassType = Context.getLocalClass()?.get();
		var pos = Context.currentPos();
		
		if (cls == null || cls.meta.has(':coreApi') || cls.meta.has(':extern') || cls.meta.has(':hlNative') || cls.meta.has(':native') ||
			cls.isInterface || cls.isExtern || cls.name.contains('_Fields_')) {
			omitted ++;
			
			if (Insanity.isVerbose() && cls != null && !cls.isInterface && !cls.name.contains('_Fields_')) {
				var path:Array<String> = cls.pack.copy(); path.push(cls.name);
				
				haxe.Log.trace('${Insanity.blobWarn} ${Insanity.ansiEsc}49;33mScriptableMacro.buildHScript${Insanity.ansiEsc}0m OMITTED ${path.join('.')} (${switch (cls) {
					case _ if (cls.meta.has(':coreApi')): 'coreApi';
					case _ if (cls.meta.has(':extern') || cls.isExtern): 'extern class';
					case _ if (cls.meta.has(':hlNative')): 'hlNative';
					case _ if (cls.meta.has(':native')): 'native';
					default: '???';
				}})', null);
			}
			
			return null;
		}
		if (cls.meta.has(':insanityScriptable')) return null;
		switch (cls.pack[0]) {
			case 'haxe' | 'hl' | 'cpp' | 'neko' | 'js' | 'cs' | 'lua' | 'php' | 'macro' | 'java' | 'flash' | 'python':
				omitted ++;
				
				if (Insanity.isVerbose()) {
					var path:Array<String> = cls.pack.copy(); path.push(cls.name);
					
					haxe.Log.trace('${Insanity.blobWarn} ${Insanity.ansiEsc}49;33mScriptableMacro.buildHscript${Insanity.ansiEsc}0m OMITTED ${path.join('.')} (internal)', null);
				}
				
				return null;
				
			case 'insanity' if (cls.name != 'InsanityDummyClass'):
				omitted ++;
				
				if (Insanity.isVerbose()) {
					var path:Array<String> = cls.pack.copy(); path.push(cls.name);
					
					haxe.Log.trace('${Insanity.blobWarn} ${Insanity.ansiEsc}49;33mScriptableMacro.buildHscript${Insanity.ansiEsc}0m OMITTED ${path.join('.')} (internal)', null);
				}
				
				return null;
				
			default:
		}
		switch (cls.kind) {
			case KAbstractImpl(_): return null;
			default:
		}
		for (ex in exclude) {
			if (cls.module.indexOf(ex) == 0) {
				for (un in unless) {
					if (cls.module.indexOf(un) == 0)
						break;
				}
				
				excluded ++;
				
				return null;
			}
		}
		if (filter != null) {
			var path:Array<String> = cls.pack.copy(); path.push(cls.name);
			
			if (!filter(path.join('.'))) return null;
		}
		
		function classHasConstructor(ccls:ClassType):Bool {
			var constr:ClassField = ccls?.constructor?.get();
			
			if (constr == null) return false;
			
			/* i fgiured out a class without a constructor FOR ITSELF actualy just uses the same pos as the entire class . kinda dirty but it gets the job done
			(checking for .constructor isnt enough since haxe fills it in automatically?) */
			return (Std.string(ccls.pos) != Std.string(constr.pos));
		}
		
		var lastClassWithConstr:Null<ClassType> = (classHasConstructor(cls) ? cls : null);
		var hasConstructor:Bool = false;
		
		var superClass = cls.superClass?.t.get();
		var su = superClass;
		
		while (true) {
			if (su == null) break;
			if (su.isExtern || su.meta.has(':coreApi') || su.meta.has(':extern') || su.meta.has(':hlNative') || su.meta.has(':native')) {
				if (Insanity.isVerbose()) {
					var path:Array<String> = cls.pack.copy(); path.push(cls.name);
					
					haxe.Log.trace('${Insanity.blobWarn} ${Insanity.ansiEsc}49;33mScriptableMacro.buildHScript${Insanity.ansiEsc}0m OMITTED ${path.join('.')} (extends ${switch (su) {
						case _ if (su.meta.has(':coreApi')): 'coreApi';
						case _ if (su.meta.has(':extern') || cls.isExtern): 'extern class';
						case _ if (su.meta.has(':hlNative')): 'hlNative';
						case _ if (su.meta.has(':native')): 'native';
						default: '???';
					}})', null);
				}
				
				return null;
			}
			
			switch (su.pack[0]) {
				case 'haxe' | 'hl' | 'cpp' | 'neko' | 'js' | 'cs' | 'lua' | 'php' | 'macro' | 'java' | 'flash' | 'python' | 'insanity':
					omitted ++;
					
					if (Insanity.isVerbose()) {
						var path:Array<String> = cls.pack.copy(); path.push(cls.name);
						
						haxe.Log.trace('${Insanity.blobWarn} ${Insanity.ansiEsc}49;33mScriptableMacro.buildHscript${Insanity.ansiEsc}0m OMITTED ${path.join('.')} (extends internal)', null);
					}
					
					return null;
					
				default:
			}
			for (ex in exclude) {
				if (su.module.indexOf(ex) == 0) {
					for (un in unless) {
						if (cls.module.indexOf(un) == 0)
							break;
					}
					
					omitted ++;
					
					if (Insanity.isVerbose()) {
						var path:Array<String> = cls.pack.copy(); path.push(cls.name);
						
						haxe.Log.trace('${Insanity.blobWarn} ${Insanity.ansiEsc}49;33mScriptableMacro.buildHscript${Insanity.ansiEsc}0m OMITTED ${path.join('.')} (extends exclusion)', null);
					}
					
					return null;
				}
			}
			
			lastClassWithConstr ??= (classHasConstructor(su) ? su : null);
			
			su = su?.superClass?.t.get();
		}
		
		var expr:Array<Expr> = [];
		var constrArgs:Array<FunctionArg> = [];
		var constrParams:Null<Array<TypeParamDecl>> = null;
		
		function getName(cls:ClassType):String {
			switch (cls.kind) {
				case KGenericInstance(cl, params):
					cls = cl.get();
					
				default:
			}
			
			var pack:Array<String> = cls.pack.copy(); pack.push(cls.name);
			
			return pack.join('_');
		}
		
		function mapConstructor(expr:Expr):Expr {
			if (expr == null) return null;
			
			return switch (expr.expr) {
				case ECall({pos: p, expr: EConst(CIdent('super'))}, params):
					{pos: expr.pos, expr: ECall({pos: p, expr: EConst(CIdent('insanitySuper${getName(lastClassWithConstr)}'))}, params)};
				
				default:
					expr.map(mapConstructor);
			}
		}
		
		for (field in fields) {
			switch (field.kind) {
				default:
				
				case FVar(t, e) if (field.access?.contains(AFinal) && !field.access.contains(AInline)):
					field.kind = FProp('default', 'null', t, e);
					field.access.remove(AFinal);
					
				case FFun(fun) if (field.name == 'new'):
					var constr = mapConstructor(fun.expr);
					switch (constr.expr) {
						case EBlock(a): for (e in a) expr.push(e);
						default: expr.push(constr);
					};
					constrParams = fun.params;
					constrArgs = fun.args;
					hasConstructor = true;
					lastClassWithConstr = cls;
			}
		}
		
		for (field in fields) {
			final f:String = field.name;
			
			for (meta in field.meta) {
				if (meta.name != ':allow') continue;
				
				switch (meta.params[0].expr) {
					case EField(e, f, a) if (f == 'new'):
						field.meta.push({
							pos: meta.pos,
							name: ':allow',
							params: [{
								pos: meta.pos,
								expr: EField(e, 'insanitySuper${e.toString().replace('.', '_')}', a) //gay
							}]
						});
						
					default:
				}
			}
			
			if (field?.access.contains(AStatic) || field?.access.contains(AInline)) continue;
			if (field.meta?.exists((meta) -> meta.name == ':deprecated')) continue;
			
			switch (field.kind) {
				default:
				
				case FProp(get, set, _, e) if (e != null && (set == 'set' || set == 'dynamic')):
					expr.unshift(macro Reflect.setField(this, $v {f}, $e));
				
				case FProp(get, set, _, e) if (e != null && set != 'set' && set != 'never'):
					expr.unshift(macro $i {f} = $e);
				
				case FVar(_, e) if (e != null):
					// trace(field.name + ' = ' + e.toString());
					expr.unshift(macro $i {f} = $e);
			}
		}
		
		if (hasConstructor || lastClassWithConstr == null) {
			if (!hasConstructor) expr = [macro throw $v {'${cls.pack.join('.') + (cls.pack.length > 0 ? '.' : '') + cls.name} does not have a constructor'}];
			
			fields.push({
				pos: pos,
				name: 'insanitySuper${getName(cls)}',
				
				kind: FFun({
					ret: macro:Void,
					expr: macro $b {expr},
					args: constrArgs,
					params: constrParams
				})
			});
		}
		
		cls.meta.add(':insanityScriptable', [macro false], pos);
		cls.meta.add(':insanitySuperName', [macro $v {'insanitySuper${getName(hasConstructor ? cls : lastClassWithConstr ?? cls)}'}], pos);
		
		return fields;
	}
	#end
	
	public static macro function listScriptableClasses():Expr {
		if (Lambda.empty(scriptableClasses)) return macro [];
		
		return macro [for (cls in $v {scriptableClasses}) cls => Type.resolveClass(cls)];
	}
}
