/*************************************************************************************

 * File:         stepperMotorControl.ino
 * Project:      Stepper motor control of a rotary table with synchronised image acquisition
 * Hardware:     Arduino UNO, A4988 driver, stepper motor, rotary table (gear ratio 45:1)
 * Operation:
 *   The motor follows a trapezoidal velocity profile:
 *   1. Acceleration:   Ramp up to the target speed.
 *   2. Constant speed: Hold the speed and send a trigger over the serial port
 *                      for every 0.5° of table rotation (for MATLAB).
 *   3. Deceleration:   Brake to a standstill after one full revolution.


 * Reference:
    https://docs.arduino.cc/hardware/uno-rev3/
    https://www.az-delivery.de/products/a4988-modul-kostenfreies-e-book
    https://www.airspayce.com/mikem/arduino/AccelStepper/classAccelStepper.html

**************************************************************************************/


#include <AccelStepper.h>

// ====================== PIN DEFINITIONS ======================
#define EN_Pin    13    // Enable pin (LOW = driver active)
#define RST_Pin   12    // Reset pin  (HIGH = normal operation)
#define SLP_Pin   11    // Sleep pin  (HIGH = awake)
#define STEP_Pin  10    // STEP pulse output to the A4988
#define DIR_Pin    9    // Direction output to the A4988

// Interrupt-capable pin on the UNO (pins 2 and 3 support attachInterrupt)
#define STObs_Pin  2    // Monitors the STEP pulses for independent step counting

// ====================== VOLATILE VARIABLES (ISR & loop) ======================
volatile long stepCount = 0;       // Steps counted since the start of the image acquisition
volatile bool triggerFlag = false; // Set by the ISR; cleared in loop() after sending over serial


// ====================== VELOCITY PROFILE PARAMETERS ======================
const float accelTime = 4;                // [s] Duration of the acceleration phase
const float maxSpeed = 3200;              // [steps/s] Target speed during the constant-speed phase
const float accel = maxSpeed/accelTime;   // [steps/s²] Acceleration (800 steps/s^2)

const int   stepsPerMotorRev = 3200;      // Steps per motor revolution (1/16 microstepping: 200 * 16)
const int   gearRatio        = 45;        // Gear ratio (45 motor revolutions = 1 table revolution)

/**
 * Kinematic step calculation:
 * Acceleration:   s = 0.5 * a * t²  =  0.5 * 800 * 16  = 6400   steps
 * Constant speed: 3200 steps/rev * 45 rev             = 144000 steps (1 full table revolution)
 * Deceleration:   Symmetric to the acceleration       = 6400   steps
 */

const long stepsAccel = (long)(0.5f * accel * accelTime * accelTime); // 6400 steps
const long stepsDecel = (long)(0.5f * accel * accelTime * accelTime); // 6400 steps
const long stepsConst = (long)stepsPerMotorRev * (long)gearRatio;     // 144000 steps

/**
 * Trigger interval: one image every 0.5° of table rotation
 * Table revolution: 360°/0.5° = 720 images per revolution
 * Motor steps per image: (stepsPerMotorRev * gearRatio) / 720 = (3200 * 45) / 720 = 200 steps
 */
const int stepRatio = 200; // A trigger signal is sent every 200 steps



// ====================== STATE MACHINE ======================
enum MotorState { Accelerate, ConstSpeed, Decelerate };


// ====================== ACCELSTEPPER INSTANCE ======================
//AccelStepper stepperMotor = AccelStepper(AccelStepper::DRIVER, STEP_Pin, DIR_Pin);
AccelStepper stepperMotor(AccelStepper::DRIVER, STEP_Pin, DIR_Pin);


// --------------------------------------------------------------------------------------------------------------

void setup() {
  // put your setup code here, to run once:

// Pin configuration
  pinMode(EN_Pin,   OUTPUT);
  pinMode(SLP_Pin,  OUTPUT);
  pinMode(RST_Pin,  OUTPUT);
  pinMode(DIR_Pin,  OUTPUT);
  pinMode(STEP_Pin, OUTPUT);

  pinMode(STObs_Pin, INPUT);

// Configure the AccelStepper limits
  stepperMotor.setMaxSpeed(maxSpeed);
  stepperMotor.setAcceleration(accel);

// Start serial communication
  Serial.begin(115200);
  Serial.println("Enter 'MotorStart' to start the motor process.");

}



void loop() {
  // put your main code here, to run repeatedly:


  if (Serial.available() > 0) {
    String command = Serial.readStringUntil('\n');  // Read the command
    command.trim(); // Remove whitespace and line breaks

    if (command == "MotorStart") {
      // --- Driver power-up sequence ---
      aktivTreiber();

      stepCount   = 0;
      triggerFlag = false;

     // Set the direction of rotation
      digitalWrite(DIR_Pin, LOW);  // Set the direction of rotation (HIGH or LOW for the other direction)

     // Calculate the target position: total distance = acceleration + constant speed + deceleration
      long startPos = stepperMotor.currentPosition();
      stepperMotor.moveTo(startPos + stepsAccel + stepsConst + stepsDecel);

     // Set the initial state
        MotorState motorState = Accelerate;

        Serial.println("MOTOR START");
        Serial.println("GET READY");

      // ----------------- Main loop of the state machine -----------------
      while(stepperMotor.distanceToGo() != 0)
      {
        // Serial.println("MotorRun");
        switch(motorState) {

          case Accelerate:
              stepperMotor.run();   // Calculates the acceleration ramp internally
              // Switch to constant speed when the remaining distance consists only of the constant-speed phase + deceleration
              if (stepperMotor.distanceToGo() <= (stepsConst + stepsDecel))  {
                motorState = ConstSpeed;
              // Fix the speed — prevents AccelStepper from calculating its own ramp during the constant-speed phase
                stepperMotor.setSpeed(maxSpeed);
              // Enable the interrupt for step counting (observation pin)
                attachInterrupt(digitalPinToInterrupt(STObs_Pin), countStepPulse, RISING); // Enable the interrupt
                Serial.println("IMAGE SHOOT START");
              }
            break;


          case ConstSpeed:
              stepperMotor.runSpeed();  // Runs at exactly constant speed
              if (triggerFlag) {
              triggerFlag = false;
              // Send the current image index to MATLAB
              noInterrupts();
              long sc = stepCount;   // Atomic snapshot of the 4-byte variable
              interrupts();

              Serial.println(stepCount / stepRatio, DEC);
            }
             // Switch to the deceleration phase
              if (stepperMotor.distanceToGo() <= stepsDecel)  {
                motorState = Decelerate;
                detachInterrupt(digitalPinToInterrupt(STObs_Pin)); // Disable the interrupt
                Serial.println("IMAGE SHOOT STOP");
              }
            break;

          case Decelerate:
            stepperMotor.run();  // Calculates the braking ramp internally
            if (stepperMotor.distanceToGo() == 0) {
              Serial.println("MOTOR STOP");
            }
            break;

        }

      }

      delay(10);
      // Disable the driver when finished
      deaktivTreiber();

    }
  }
}




// -------------------------------- Helper functions -------------------------------- //

/**
 * Enables the A4988 driver
 */
void aktivTreiber()
{
  digitalWrite(EN_Pin,  LOW);   // Enable the driver (active LOW)
  digitalWrite(SLP_Pin, HIGH);  // Wake up from sleep mode
  digitalWrite(RST_Pin, HIGH);  // Release reset
}

/**
 * Disables the A4988 driver (power-saving mode)
 */
void deaktivTreiber()
{
  digitalWrite(SLP_Pin, LOW);   // Enter sleep mode
  digitalWrite(RST_Pin, LOW);   // Assert reset
  digitalWrite(EN_Pin,  HIGH);  // Switch off the outputs
}


/**
 * ISR (Interrupt Service Routine)
 * Called on every rising edge of the STEP pulse.
 */
void countStepPulse() {
  stepCount++;
  // Check whether the interval for an image trigger has been reached
  if (stepCount % stepRatio == 0) {
    triggerFlag = true; // Set the flag so that the loop sends the serial trigger
  }
}
