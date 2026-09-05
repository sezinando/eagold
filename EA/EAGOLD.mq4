//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|                         EAGOLD - Expert Advisor for MT4          |
//+------------------------------------------------------------------+
#property strict
#property version   "0.1.0"
#property description "Initial EAGOLD EA skeleton."

input int MagicNumber = 1001;
input double Lots = 0.01;

int OnInit()
  {
   Print("EAGOLD initialized. MagicNumber=", MagicNumber,
         " Lots=", DoubleToString(Lots, 2));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   Print("EAGOLD deinitialized. Reason=", reason);
  }

void OnTick()
  {
   // Strategy engine will be implemented in subsequent versions.
  }
//+------------------------------------------------------------------+
