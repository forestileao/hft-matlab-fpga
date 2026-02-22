
#include "SimpleMD.h"
#include <iostream>
#include <iomanip>
#include <map>
#include <vector>
#include "fast_data_feed.h"

int main()
{
  SimpleMD::SimpleMD message;
  SimpleMD::SimpleMD_mref ref = message.ref();
  ref.set_MDEntries().resize(1);
  SimpleMD::SimpleMD_mref::MDEntries_element_mref entry(ref.set_MDEntries()[0]);

  entry.set_Symbol().as("AAPL");
  entry.set_Side().as("buy");
  entry.set_Price().as(150.25);
  entry.set_Qty().as(1000);

  message_printer printer(std::cout);
  printer.visit(ref, 0);
  return 0;
}
