//+------------------------------------------------------------------+
//| ZEUS_REPLICA.mq4                                                 |
//| ZEUS Replica - clean bootstrap / Strategy Tester diagnostic      |
//|                                                                  |
//| V0.1                                                             |
//|                                                                  |
//| PURPOSE                                                          |
//|   This file is intentionally rebuilt from zero.                  |
//|   V0.1 validates only the MT4 execution lifecycle:              |
//|                                                                  |
//|      OnInit -> first OnTick -> market data -> OrderSend          |
//|                                                                  |
//|   No ZEUS ladder, trailing or exit logic is present yet.         |
//|   Behavioral reconstruction starts only after this boot layer    |
//|   is proven to execute correctly in Strategy Tester.             |
//+------------------------------------------------------------------+
#property strict
#property version   "0.1"
#property description "ZEUS Replica V0.1 - clean bootstrap diagnostic"

input int      Magic       = 1001;
input double   Lots        = 0.01;
input int      FirstStep   = 160;
input int      MaxSpread   = 100;
input bool     SendInitialOrders = true;
input bool     EnableLogs  = true;

bool g_first_tick = false;
bool g_buy_sent   = false;
bool g_sell_sent  = false;

void Log(string text)
{
   if(EnableLogs)
      Print("ZEUS_REPLICA | ",text);
}

string BoolText(bool value)
{
   return(value ? "true" : "false");
}

bool IsOurPending(int type)
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;

      if(OrderSymbol()!=Symbol())
         continue;

      if(OrderMagicNumber()!=Magic)
         continue;

      if(OrderType()==type)
         return(true);
   }

   return(false);
}

void PrintEnvironment()
{
   RefreshRates();

   double spread_points = 0.0;
   if(Point>0.0)
      spread_points=(Ask-Bid)/Point;

   Log("ENV | testing="+BoolText(IsTesting())+
       " symbol="+Symbol()+
       " period="+IntegerToString(Period())+
       " digits="+IntegerToString(Digits)+
       " point="+DoubleToString(Point,Digits));

   Log("ENV | bid="+DoubleToString(Bid,Digits)+
       " ask="+DoubleToString(Ask,Digits)+
       " spread_points="+DoubleToString(spread_points,1));

   Log("ENV | trade_allowed="+BoolText(IsTradeAllowed())+
       " symbol_trade_allowed="+DoubleToString(MarketInfo(Symbol(),MODE_TRADEALLOWED),0));

   Log("ENV | stop_level="+DoubleToString(MarketInfo(Symbol(),MODE_STOPLEVEL),0)+
       " freeze_level="+DoubleToString(MarketInfo(Symbol(),MODE_FREEZELEVEL),0));

   Log("ENV | min_lot="+DoubleToString(MarketInfo(Symbol(),MODE_MINLOT),2)+
       " lot_step="+DoubleToString(MarketInfo(Symbol(),MODE_LOTSTEP),2)+
       " max_lot="+DoubleToString(MarketInfo(Symbol(),MODE_MAXLOT),2));
}

double NormalizeLots(double value)
{
   double min_lot  = MarketInfo(Symbol(),MODE_MINLOT);
   double max_lot  = MarketInfo(Symbol(),MODE_MAXLOT);
   double lot_step = MarketInfo(Symbol(),MODE_LOTSTEP);

   if(value<min_lot)
      value=min_lot;

   if(value>max_lot)
      value=max_lot;

   if(lot_step>0.0)
      value=MathFloor(value/lot_step+1e-8)*lot_step;

   if(value<min_lot)
      value=min_lot;

   return(NormalizeDouble(value,2));
}

bool SendInitial(int type)
{
   RefreshRates();

   double spread_points=(Ask-Bid)/Point;
   if(spread_points>MaxSpread)
   {
      Log("SEND | REJECT | spread="+DoubleToString(spread_points,1)+
          " > MaxSpread="+IntegerToString(MaxSpread));
      return(false);
   }

   double lots=NormalizeLots(Lots);
   double price=0.0;
   string side="";

   if(type==OP_BUYSTOP)
   {
      price=NormalizeDouble(Ask+FirstStep*Point,Digits);
      side="BUY STOP";
   }
   else if(type==OP_SELLSTOP)
   {
      price=NormalizeDouble(Bid-FirstStep*Point,Digits);
      side="SELL STOP";
   }
   else
   {
      Log("SEND | ERROR | unsupported order type");
      return(false);
   }

   double stop_level=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;

   if(type==OP_BUYSTOP && price<=Ask+stop_level)
   {
      Log("SEND | REJECT | BUY STOP distance below broker stop level | price="+
          DoubleToString(price,Digits)+" ask="+DoubleToString(Ask,Digits));
      return(false);
   }

   if(type==OP_SELLSTOP && price>=Bid-stop_level)
   {
      Log("SEND | REJECT | SELL STOP distance below broker stop level | price="+
          DoubleToString(price,Digits)+" bid="+DoubleToString(Bid,Digits));
      return(false);
   }

   Log("SEND | ATTEMPT | side="+side+
       " lots="+DoubleToString(lots,2)+
       " price="+DoubleToString(price,Digits));

   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,price,0,0,0,"ZEUS_REPLICA_BOOT",Magic,0,clrNONE);
   int error=GetLastError();

   if(ticket<0)
   {
      Log("SEND | ERROR | side="+side+
          " error="+IntegerToString(error)+
          " price="+DoubleToString(price,Digits)+
          " lots="+DoubleToString(lots,2));
      return(false);
   }

   Log("SEND | SUCCESS | side="+side+
       " ticket="+IntegerToString(ticket)+
       " price="+DoubleToString(price,Digits)+
       " lots="+DoubleToString(lots,2));

   return(true);
}

void BootOrders()
{
   if(!SendInitialOrders)
   {
      Log("BOOT | order sending disabled by input");
      return;
   }

   if(!IsOurPending(OP_BUYSTOP))
      g_buy_sent=SendInitial(OP_BUYSTOP);
   else
      Log("BOOT | BUY STOP already exists");

   if(!IsOurPending(OP_SELLSTOP))
      g_sell_sent=SendInitial(OP_SELLSTOP);
   else
      Log("BOOT | SELL STOP already exists");
}

int OnInit()
{
   Log("============================================================");
   Log("INIT | ZEUS_REPLICA V0.1");
   Log("INIT | OnInit entered successfully");
   Log("INIT | Symbol="+Symbol()+" Magic="+IntegerToString(Magic));
   PrintEnvironment();
   Log("INIT | returning INIT_SUCCEEDED");
   Log("============================================================");

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Log("DEINIT | reason="+IntegerToString(reason));
}

void OnTick()
{
   RefreshRates();

   if(!g_first_tick)
   {
      g_first_tick=true;

      Log("============================================================");
      Log("TICK | FIRST TICK RECEIVED");
      Log("TICK | Time="+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
      Log("TICK | Bid="+DoubleToString(Bid,Digits)+
          " Ask="+DoubleToString(Ask,Digits));
      Log("TICK | OnTick lifecycle confirmed");
      Log("============================================================");

      BootOrders();
      return;
   }
}

//+------------------------------------------------------------------+
