class_name LaunchProfile extends RefCounted
## Kid-sized launch physics. Three things decide whether the rocket reaches
## orbit:
##   - Thrust: the engines must push harder than the rocket weighs. Every ton
##     (capsule, cargo, engines, tanks) needs THRUST_PER_TON of thrust.
##     Engine and booster cards add "thrust".
##   - Fuel: every engine burns fuel at take-off ("fuel_burn"), and the tanks
##     must hold enough for all of them. Tank cards add "fuel" (some lose a
##     bit before take-off: "fuel_leak").
##   - Reliability: a small chance of a glitch. More thrust helps a little,
##     some cards change it directly ("reliability", in %).
## Every card adds its `weight` to the rocket.

## Crew capsule with the crew inside, always on board.
const CAPSULE_TONS: float = 8.0
## Thrust needed for every ton of rocket.
const THRUST_PER_TON: float = 10.0
## The stock engines, and the stock tanks that feed them.
const BASE_THRUST: float = 160.0
const BASE_FUEL_BURN: float = 100.0
const BASE_FUEL: float = 130.0
const BASE_RELIABILITY: float = 0.94
## Every point of extra thrust makes the launch a little more reliable.
const RELIABILITY_PER_THRUST: float = 0.00005
const MAX_RELIABILITY: float = 0.99

## Thrust ratio (thrust / thrust needed) below which the rocket can't climb,
## and above which it climbs comfortably.
const THRUST_MIN: float = 0.9
const THRUST_SAFE: float = 1.3
## Fuel ratio (fuel / fuel the engines burn) below which orbit is out of
## reach, and above which there is a comfortable margin.
const FUEL_MIN: float = 0.7
const FUEL_SAFE: float = 1.05

enum Failure {
    NONE,
    ## Too heavy for the engines: shut down safely on the pad.
    THRUST,
    ## Not enough fuel to reach orbit: the capsule parachutes back.
    FUEL,
    ## A sensor glitch: launch held on the pad.
    GLITCH,
}

var cargo_tons: float = 0.0
var thrust: float = BASE_THRUST
var fuel_burn: float = BASE_FUEL_BURN
## Fuel loaded in the tanks, before leaks.
var fuel: float = BASE_FUEL
var fuel_leak: float = 0.0
## Extra reliability from cards (0.03 = +3%).
var reliability_bonus: float = 0.0

var _augments: Array[Augment] = []


static func from_instances(instances: Array[AugmentInstance]) -> LaunchProfile:
    var augments: Array[Augment] = []
    for instance in instances:
        augments.append(instance.augment)
    return from_augments(augments)


static func from_augments(augments: Array[Augment]) -> LaunchProfile:
    var profile := LaunchProfile.new()
    profile._augments = augments.duplicate()
    for augment in augments:
        profile.cargo_tons += augment.weight
        profile._add_keys(augment.upgrades)
        if not augment.launch_synergy.is_empty() and augments.any(func(a: Augment): return a != augment and augment.is_synergy_partner(a)):
            profile._add_keys(augment.launch_synergy)
    return profile


func _add_keys(keys: Dictionary[String, String]) -> void:
    thrust += float(keys.get("thrust", "0"))
    fuel += float(keys.get("fuel", "0"))
    fuel_burn += float(keys.get("fuel_burn", "0"))
    fuel_leak += float(keys.get("fuel_leak", "0"))
    reliability_bonus += float(keys.get("reliability", "0")) / 100.0


## A copy of this profile with one more card loaded, for previews.
func with_augment(augment: Augment) -> LaunchProfile:
    var augments := _augments.duplicate()
    augments.append(augment)
    return from_augments(augments)


func total_weight() -> float:
    return CAPSULE_TONS + cargo_tons


func thrust_needed() -> float:
    return total_weight() * THRUST_PER_TON


## Thrust / thrust needed. Below 1 the rocket can't leave the pad.
func thrust_ratio() -> float:
    return thrust / maxf(thrust_needed(), 0.001)


func is_overweight() -> bool:
    return thrust_ratio() < 1.0


## Fuel left in the tanks at take-off.
func fuel_available() -> float:
    return maxf(0.0, fuel - fuel_leak)


## Fuel the engines burn on the way to orbit.
func fuel_needed() -> float:
    return fuel_burn


func fuel_ratio() -> float:
    return fuel_available() / maxf(fuel_needed(), 0.001)


func thrust_factor() -> float:
    return smoothstep(THRUST_MIN, THRUST_SAFE, thrust_ratio())


func fuel_factor() -> float:
    return smoothstep(FUEL_MIN, FUEL_SAFE, fuel_ratio())


func reliability() -> float:
    return clampf(BASE_RELIABILITY + (thrust - BASE_THRUST) * RELIABILITY_PER_THRUST + reliability_bonus, 0.0, MAX_RELIABILITY)


## Chance from 0.0 to 1.0 that the rocket reaches orbit.
func success_chance() -> float:
    return clampf(reliability() * thrust_factor() * fuel_factor(), 0.0, 1.0)


## Rolls the launch. Returns Failure.NONE on success, otherwise the cause,
## picked in proportion to how much each factor hurt the odds.
func roll(rng: RandomNumberGenerator = null) -> Failure:
    var r: float = rng.randf() if rng != null else randf()
    if r < success_chance():
        return Failure.NONE
    var weights: Dictionary[Failure, float] = {
        Failure.THRUST: 1.0 - thrust_factor(),
        Failure.FUEL: 1.0 - fuel_factor(),
        Failure.GLITCH: 1.0 - reliability(),
    }
    var total := 0.0
    for w in weights.values():
        total += w
    var pick: float = (rng.randf() if rng != null else randf()) * total
    for failure in weights.keys():
        pick -= weights[failure]
        if pick <= 0.0:
            return failure
    return Failure.GLITCH


## The biggest problem right now, as a short hint for the player.
func advice() -> String:
    if thrust_factor() >= 0.999 and fuel_factor() >= 0.999:
        return "Looking good!"
    if thrust_factor() < fuel_factor():
        return "Too heavy: add engines or lighter cargo"
    return "Low on fuel: add fuel tanks"


## What worries mission control most, once the cargo is locked in.
func main_problem() -> String:
    if thrust_factor() >= 0.999 and fuel_factor() >= 0.999:
        return "no known issues"
    if thrust_factor() < fuel_factor():
        return "the rocket is heavy for its engines"
    return "the engines may run out of fuel before orbit"
