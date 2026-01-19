package insanity;

import insanity.custom.*;
#if hl import insanity.custom.HL; #end

class Config {
	@:unreflective public static var typeProxy:Map<String, Dynamic> = [
		#if hl
		'Math' => HLMath,
		#end
		
		'Reflect' => InsanityReflect,
		'Type' => InsanityType,
		'Std' => InsanityStd
	];
}