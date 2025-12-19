package insanity;

import insanity.custom.*;

class Config {
	@:unreflective public static var typeProxy:Map<String, Dynamic> = [
		'Reflect' => InsanityReflect,
		'Type' => InsanityType
	];
}