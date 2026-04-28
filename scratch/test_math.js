// Mock data
const estimate1RM = (weight, reps, rir = 0) => {
  const actualReps = reps + rir;
  if (actualReps === 0) return 0;
  return weight / (1.0278 - (0.0278 * actualReps));
};

const calculateTargetLoadFrom1RM = (e1RM, goal) => {
  let intensity = 0.75; // Default 75% for Muscle
  let reps = 10;
  
  if (goal === 'build_strength') {
    intensity = 0.85;
    reps = 5;
  }
  
  let weight = Math.round((e1RM * intensity) / 2.5) * 2.5;
  weight = Math.max(20, weight);
  return { weight, reps };
};

const lastSet = { weight: "98", reps: "1", rir: "0" };
const e1RM = estimate1RM(parseFloat(lastSet.weight), parseInt(lastSet.reps), parseInt(lastSet.rir));
console.log("e1RM:", e1RM);

const target = calculateTargetLoadFrom1RM(e1RM, "build_muscle");
console.log("Target:", target);
