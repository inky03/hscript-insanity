package;

import Std;
import haxe.Timer;

import insanity.Script;

class Main {
	static function main():Void {
		var script:Script = new Script('
			import Std;
			import haxe.Timer;
			import haxe.Timer as Helloween;
			
			var testMap:Map<String, Dynamic> = [];
			testMap.set("hello", 3);
			trace(testMap);
			
			function crashFun() {
				test = 4;
			}
			function fun() {
				crashFun();
			}
			function theTime() {
				trace(Helloween.stamp());
			}
			var fucj = () -> fun();
			
			trace("test script Hello");
			
			fucj();
			
			var test:Float = 3;
			trace(test);
			
			trace("hellow");
		', 'TestScript');
		
		script.execute();
		
		script.call('theTime', []);
		/*try {
			var agray:Dynamic = [];
			agray.set('hello', 3);
		} catch(e:haxe.Exception) {
			trace(e.details());
		}*/
	}
}