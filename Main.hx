package;

import Std;
import haxe.Timer;

import insanity.Script;

class Main {
	static function main():Void {
		var script:Script = new Script('
			import Std;
			import haxe.Timer;
			
			var fuc = 1;
			
			trace("hellow");
			trace(Timer.stamp());
		');
	}
}