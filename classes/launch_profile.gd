class_name LaunchProfile extends RefCounted
## Kid-sized launch physics (all masses in tons). Three things decide whether the rocket reaches
## orbit:
##   - Lift: can the engines carry the capsule plus all the cargo?
##     Upgraded with the "engine_thrust" augment key (tons of extra lift).
##   - Fuel: is there enough propellant to push that weight all the way up?
##     Upgraded with the "fuel" augment key (tons of extra propellant).
##   - Reliability: a small chance of a glitch. Better engines help.
## Every augment adds its `weight` to the cargo.

## Crew capsule with the crew inside, always on board.
const CAPSULE_TONS: float = 8.0
## Tons the stock engines can carry to orbit.
const BASE_LIFT_TONS: float = 18.0
## Propellant in the stock tanks.
const BASE_FUEL_TONS: float = 60.0
## Tons of propellant needed for every ton carried to orbit.
const FUEL_PER_TON: float = 5.0
const BASE_RELIABILITY: float = 0.94
## Every extra ton of engine lift also makes the engines a bit more reliable.
const RELIABILITY_PER_LIFT_TON: float = 0.005

## Load (weight / lift) below which the engines are comfortable, and above
## which the rocket cannot leave the pad at all.
const LOAD_SAFE: float = 0.8
const LOAD_MAX: float = 1.2
## Fuel ratio (fuel / fuel needed) below which orbit is out of reach, and
## above which there is a comfortable margin.
const FUEL_MIN: float = 0.7
const FUEL_SAFE: float = 1.1

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
var lift_tons: float = BASE_LIFT_TONS
var fuel_tons: float = BASE_FUEL_TONS


static func from_instances(instances: Array[AugmentInstance]) -> LaunchProfile:
    var profile := LaunchProfile.new()
    for instance in instances:
        profile.add(instance.augment)
    return profile


func add(augment: Augment) -> void:
    cargo_tons += augment.weight
    lift_tons += float(augment.upgrades.get("engine_thrust", "0"))
    fuel_tons += float(augment.upgrades.get("fuel", "0"))


## A copy of this profile with one more augment loaded, for previews.
func with_augment(augment: Augment) -> LaunchProfile:
    var copy := LaunchProfile.new()
    copy.cargo_tons = cargo_tons
    copy.lift_tons = lift_tons
    copy.fuel_tons = fuel_tons
    copy.add(augment)
    return copy


func total_weight() -> float:
    return CAPSULE_TONS + cargo_tons


func load_ratio() -> float:
    return total_weight() / maxf(lift_tons, 0.001)


func is_overweight() -> bool:
    return total_weight() > lift_tons


func fuel_needed() -> float:
    return total_weight() * FUEL_PER_TON


func fuel_ratio() -> float:
    return fuel_tons / maxf(fuel_needed(), 0.001)


func thrust_factor() -> float:
    return 1.0 - smoothstep(LOAD_SAFE, LOAD_MAX, load_ratio())


func fuel_factor() -> float:
    return smoothstep(FUEL_MIN, FUEL_SAFE, fuel_ratio())


func reliability() -> float:
    return clampf(BASE_RELIABILITY + (lift_tons - BASE_LIFT_TONS) * RELIABILITY_PER_LIFT_TON, 0.0, 1.0)


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
        return "Too heavy: add engine upgrades or lighter cargo"
    return "Low on fuel: add fuel tanks"


## What worries mission control most, once the cargo is locked in.
func main_problem() -> String:
    if thrust_factor() >= 0.999 and fuel_factor() >= 0.999:
        return "no known issues"
    if thrust_factor() < fuel_factor():
        return "the rocket is heavy for its engines"
    return "fuel is tight to reach orbit"
