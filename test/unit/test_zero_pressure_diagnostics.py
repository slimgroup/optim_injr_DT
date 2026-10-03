"""Small analytical cases for the scientific pressure audit, no reservoir runs."""
import importlib.util
from pathlib import Path
import unittest
import numpy as np

spec=importlib.util.spec_from_file_location("zero_audit",Path(__file__).resolve().parents[2]/"scripts/python_tools/analysis/summarize_zero_pressure_audit.py")
audit=importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

class PressureDiagnostics(unittest.TestCase):
    def test_strict_crossing_time_and_cell_mask(self):
        p0=np.array([[1e6,2e6],[3e6,4e6]])
        p=np.stack([p0+3e6,p0+np.array([[3e6+1,0],[0,0]])])
        times=np.array([8,16])
        r=audit.metric(p,p0,times,3,np.ones((2,2),bool))
        self.assertEqual(r["exceeding_cell_times"],1)
        self.assertEqual(r["exact_cell_time_pof"],1/8)
        self.assertEqual(r["first_exceedance_day"],16)
        self.assertEqual((r["max_overpressure_x_index"],r["max_overpressure_z_index"]),(1,1))
        self.assertEqual(r["max_pressure_excess_pa"],1)
        self.assertEqual(r["min_pressure_margin_pa"],-1)
        for delta in (4,5):
            self.assertFalse(audit.metric(p,p0,times,delta,np.ones((2,2),bool))["any_exceedance_exact"])
        masked=audit.metric(p,p0,times,3,np.array([[False,True],[True,True]]))
        self.assertEqual(masked["cell_time_denominator"],6)
        self.assertEqual(masked["exceeding_cell_times"],0)

    def test_fractional_cvar_last_weight(self):
        p0=np.full((1,150),1e6)
        pressure=np.full((1,1,150),4e6)
        pressure[0,0,:2]=[8e6,6e6]  # losses 1 and 0.5; alpha*N=1.5 entries
        r=audit.metric(pressure,p0,np.array([8]),3,np.ones((1,150),bool))
        self.assertAlmostEqual(r["clean_cvar_alpha001"],(1+0.5*0.5)/1.5)

    def test_limit_changes_relative_margin_denominator(self):
        p0=np.array([[1e6]])
        p=np.array([[[7e6]]])
        for delta in (3,4,5):
            r=audit.metric(p,p0,np.array([8]),delta,np.ones((1,1),bool))
            self.assertAlmostEqual(r["clean_cvar_alpha001"],(6-delta)/(1+delta))

    def test_logistic_is_not_exact_pof(self):
        r=audit.metric(np.array([[[4e6]]]),np.array([[1e6]]),np.array([8]),3,np.ones((1,1),bool))
        self.assertEqual(r["exact_cell_time_pof"],0)
        self.assertEqual(r["logistic_pof_tau005"],0.5)

if __name__=="__main__": unittest.main()
